extends RefCounted
## Top-down pixel-art VEST painter (Character domain, private; rendered through the Art domain's
## PixelArt as part of the shoulders, body_painter.gd, which calls it over their shirt). Two
## garments, from the look's `vest` kind (`OutfitConfig` looks): a soft tactical `vest` — a padded
## panel over the trunk that leaves the shoulder caps bare (a merc wears it as a chest rig: webbing
## straps, a row of pouches and one on each flank) — and a plate `carrier` — a front and a back
## panel joined by shoulder straps and a cummerbund, pouches across the front, a drag handle on the
## back, each panel bulging where a plate sits in it (a crew's panels mismatched: `front_cover`,
## `back_cover`). Each style marks it: the Zenitex's white stencil along the front and back edges
## with a red lamp, the Trauma Team's red cross, a borg's welded steel and rivets. A plate's wear
## shows on its panel as scuffs and cracks with the plate showing through, more of them at each wear
## step. Options (`opts`): `look` (a `PixelArt.handle`: `vest`, `vest_col`, the covers, the style)
## and per side (`front_` / `back_`) `<side>plate` (the plate's colour; absent = no plate) and
## `<side>wear` (0 new .. `WEAR_STEPS` spent).

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")
## Heights for cast shadows, floor-up: over the shirt (4), under the head's ring.
const _VEST := 5
const _PLATE := 6
const _POUCH := 7
const _MARK := 8
## The wear steps a plate's condition is rounded to (its marks grow with each; the art repaints only
## when the step changes).
const WEAR_STEPS := 4
## Scuffs and cracks added per wear step.
const _MARKS_PER_STEP := 2
## Buckles and webbing.
const _STRAP := Color(0.10, 0.10, 0.09)


## The vest seen from above, over the shoulders ellipse `span` of a canvas centred on `o` (front
## toward +y).
static func paint_top(c: PixelCanvas, o: Vector2i, span: Rect2i, opts: Dictionary) -> void:
	var look := PixelArt.look_of(opts)
	var kind := String(look.get("vest", ""))
	if kind == "":
		return
	if kind == "vest":
		_top_vest(c, o, span, look)
		return
	_top_carrier(c, o, span, opts)


## A soft vest from above: a merc's chest rig, or the padded panel cut to the shoulders.
static func _top_vest(c: PixelCanvas, o: Vector2i, span: Rect2i, look: Dictionary) -> void:
	if String(look.get("style", "")) == "merc":
		_top_chest_rig(c, o, span, look)
		return
	var half := roundi(c.w * 0.3)
	# The panel hugs the shoulders: a rounded block across the trunk, cut to the shoulders' own
	# outline.
	var block := PixelShape.rounded(
		Rect2i(o.x - half, span.position.y, half * 2 + 1, span.size.y),
		4,
	)
	var shoulders := PixelShape.ellipse(span)
	var body := PixelShape.new(
		block.bounds,
		func(x: int, y: int) -> bool: return block.has(x, y) and shoulders.has(x, y),
	)
	_fill(c, body, _col(look, "vest_col"), false, look)
	_marks_top(c, o, span, look, "vest")


## A merc's chest rig from above: dark webbing straps over both shoulders, a pouch on each flank and
## a row across the front (what shows past the head from above, whatever drab top is under them).
static func _top_chest_rig(c: PixelCanvas, o: Vector2i, span: Rect2i, look: Dictionary) -> void:
	var half := roundi(c.w * 0.3)
	var col := _col(look, "vest_col")
	for side in [-1, 1]:
		for dx in [0, 1]:
			var x: int = o.x + side * (half - 3 + dx)
			c.line(Vector2i(x, span.position.y + 1), Vector2i(x, span.end.y - 2), _STRAP, _VEST)
		var flank := PixelShape.rounded(
			Rect2i(o.x + side * (half - 1) - (2 if side > 0 else 0), o.y - 2, 3, 5),
			0,
		)
		c.fill(flank, col.darkened(0.1), _POUCH)
		c.outline(flank, _STRAP)
	_pouches(c, Rect2i(o.x - half, span.end.y - 4, half * 2 + 1, 3), 4, col)


## A plate carrier from above: shoulder straps beside the neck between the front and back panels.
static func _top_carrier(c: PixelCanvas, o: Vector2i, span: Rect2i, opts: Dictionary) -> void:
	var look := PixelArt.look_of(opts)
	var half := roundi(c.w * 0.3)
	var t := ArtSurfaceConfig.tones(_col(look, "vest_col"))
	for side in [-1, 1]:
		c.line(
			Vector2i(o.x + side * (half - 2), span.position.y),
			Vector2i(o.x + side * (half - 2), span.end.y - 1),
			t.dark,
			_VEST,
		)
	for face in ["front", "back"]:
		_top_panel(c, o, span, opts, face)
	_marks_top(c, o, span, look, "carrier")


## The carrier's `face` ("front" | "back") panel from above: its plate's wear, the pouches in front
## or the drag handle behind.
static func _top_panel(
	c: PixelCanvas,
	o: Vector2i,
	span: Rect2i,
	opts: Dictionary,
	face: String,
) -> void:
	var look := PixelArt.look_of(opts)
	var half := roundi(c.w * 0.3)
	var front := face == "front"
	var y := span.end.y - 4 if front else span.position.y - 2
	var panel := PixelShape.rounded(Rect2i(o.x - half, y, half * 2 + 1, 6), 2)
	var plated: bool = opts.has(face + "_plate")
	var cover := _col(look, face + "_cover")
	_fill(c, panel, cover, plated, look)
	if plated:
		_wear(c, panel.bounds.grow(-1), face, opts, cover)
	if front:
		_pouches(c, Rect2i(o.x - half + 1, y + 3, half * 2 - 1, 3), 3, cover)
	else:
		c.line(Vector2i(o.x - 1, y + 1), Vector2i(o.x + 1, y + 1), _STRAP, _POUCH)


## A panel `s` in `col`: its finish (the look's style's: a borg's welded steel, else fabric), a
## bevel (raised where a plate sits), the livery's edge sheen and an outline; a plate's panel stands
## higher.
static func _fill(
	c: PixelCanvas,
	s: PixelShape,
	col: Color,
	plated: bool,
	look: Dictionary,
) -> void:
	var t := ArtSurfaceConfig.tones(col)
	var finish := "metal" if String(look.get("style", "")) == "borg" else "fabric"
	c.fill(s, col, _PLATE if plated else _VEST)
	c.surface(s, finish, col)
	c.bevel(s, 1, 2 if plated else 1, t.highlight if plated else t.light, t.dark)
	StyleArt.edge(c, s, look)
	if not StyleArt.flat(c):
		c.outline(s, t.outline)


## `count` pouches side by side across `r`, a shade darker than `col`, each with its flap.
static func _pouches(c: PixelCanvas, r: Rect2i, count: int, col: Color) -> void:
	var pc := col.darkened(0.18)
	var t := ArtSurfaceConfig.tones(pc)
	var w := maxi(2, int(r.size.x / float(count)) - 1)
	for k in count:
		var pouch := PixelShape.rounded(
			Rect2i(r.position.x + k * (w + 1), r.position.y, w, r.size.y),
			0,
		)
		c.fill(pouch, pc, _POUCH)
		var flap: Color = t.base if StyleArt.flat(c) else t.light  # The flap's lit edge.
		if not StyleArt.flat(c):
			c.outline(pouch, t.outline)
		c.line(
			Vector2i(pouch.bounds.position.x, r.position.y),
			Vector2i(pouch.bounds.end.x - 1, r.position.y),
			flap,
			_POUCH,
		)


## The look's colour `key`, or a drab green.
static func _col(look: Dictionary, key: String) -> Color:
	return look.get(key, Color(0.24, 0.27, 0.22))


## The style's marks on the vest from above. The head hides the middle of the chest and back (about
## 6 px round `o`), so each sits clear of it: the Zenitex's white stencil along the front and back
## edges and its red lamp, the Trauma Team's cross, a borg's rivets.
static func _marks_top(
	c: PixelCanvas,
	o: Vector2i,
	span: Rect2i,
	look: Dictionary,
	kind: String,
) -> void:
	var half := roundi(c.w * 0.3)
	var trim: Color = look.get("trim", Color.WHITE)
	var chest := span.end.y - 3 if kind == "vest" else span.end.y - 5
	var front_edge := span.end.y - 2 if kind == "vest" else span.end.y + 1
	var back_edge := span.position.y + 1 if kind == "vest" else span.position.y - 1
	match String(look.get("style", "")):
		"zenitex":
			StyleArt.stencil(c, Vector2i(o.x - half + 2, front_edge), half * 2 - 3, trim, _MARK)
			StyleArt.stencil(c, Vector2i(o.x - half + 2, back_edge), half * 2 - 3, trim, _MARK)
			c.px(o.x + half - 1, chest, look.get("led", Color.RED), _MARK)
		"trauma":
			StyleArt.cross(c, Vector2i(o.x, chest), trim, _MARK)
		"borg":
			for side in [-1, 1]:
				c.px(o.x + side * (half - 1), chest, Color(0.2, 0.2, 0.2), _MARK)
				c.px(o.x + side * (half - 1), span.position.y + 2, Color(0.2, 0.2, 0.2), _MARK)


## A plate's wear on its panel: `_MARKS_PER_STEP` marks per wear step inside `r`, alternating a
## crack (a short dark zigzag) and a scuff torn through to the plate. The marks come from one fixed
## sequence per side, so each step adds to the last step's.
static func _wear(c: PixelCanvas, r: Rect2i, face: String, opts: Dictionary, panel: Color) -> void:
	var steps := clampi(int(opts.get(face + "_wear", 0)), 0, WEAR_STEPS)
	if steps == 0 or r.size.x < 2 or r.size.y < 2:
		return
	var plate: Color = opts[face + "_plate"]
	var crack := panel.darkened(0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(face)
	for k in steps * _MARKS_PER_STEP:
		var p := Vector2i(
			rng.randi_range(r.position.x, r.end.x - 1),
			rng.randi_range(r.position.y, r.end.y - 1),
		)
		if k % 2 == 0:
			var q := p
			for i in 3:
				c.px(q.x, q.y, crack)
				q += Vector2i(1 if rng.randf() < 0.5 else -1, 1 if i % 2 == 0 else 0)
				q = q.clamp(r.position, r.end - Vector2i.ONE)
		else:
			c.px(p.x, p.y, plate.lightened(0.15))
			c.px(mini(p.x + 1, r.end.x - 1), p.y, plate)
