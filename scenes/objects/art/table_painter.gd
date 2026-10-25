extends RefCounted
## Top-down pixel-art TABLE painter (Objects domain, private). A planked wooden top — planks
## along the long side with dark seams, staggered butt joints, a slight tone per plank, grain and
## the odd knot — inside a light-aware bevelled rim with rounded corners, optionally dressed with
## props. Options (`art_opts`, defaulting to ObjectArtConfig.table_*): `plank_px`, `rim_px`,
## `corner_radius`, `inset` (a recessed centre panel), `runner` (a cloth runner down the long
## axis), `gaps` (open slats, as on a bench), `props` and `neon` (a desk's: its screens and a neon
## strip set round its edge, glowing). Run down like a chair (scratches, cup rings, burns). A table
## is symmetric, so its facing only turns the plank direction with the footprint.

const Props = preload("res://scenes/objects/art/props.gd")
const ChairPainter = preload("res://scenes/objects/art/chair_painter.gd")
const Decay = preload("res://scenes/objects/art/decay.gd")
## Tabletop height, for cast shadows.
const _TOP_HEIGHT := 2
## The runner sits on the top.
const _RUNNER_HEIGHT := 3


## Paint a table onto `c` in `base` wood.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var radius: int = opts.get("corner_radius", ObjectArtConfig.table_corner_radius)
	var rim: int = opts.get("rim_px", ObjectArtConfig.table_rim_px)
	var top := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), radius)

	c.fill(top, base, _TOP_HEIGHT)
	var seams := _planks(c, base, t, opts)
	if opts.get("inset", ObjectArtConfig.table_inset):
		_inset(c, radius, base, t, opts)
	c.bevel(top, 2, 2, t.highlight, t.shadow)
	c.bevel(top, 3, 1 + rim, t.light, t.dark)
	c.outline(top, t.outline)
	if opts.get("gaps", false):
		for a in seams:
			c.clear(PixelCanvas.rounded(
				Rect2i(0, a, c.w, 1) if c.w >= c.h else Rect2i(a, 0, 1, c.h),
				0,
			))
	if opts.get("runner", ObjectArtConfig.table_runner):
		_runner(c)
	Props.draw_all(
		c,
		opts.get("props", []),
		Rect2i(0, 0, c.w, c.h).grow(-3),
		Decay.screen_color(opts),
	)
	c.cast_shadows()
	ChairPainter.worn_wood(c)
	var neon := Decay.neon(opts)
	if neon.a > 0.0:
		Decay.neon_ring(c, 1, neon, 0.45)


## Planks along the long side: per-plank tone, grain and knots, seams between planks and
## staggered butt joints on long ones. Returns the seam positions across the planks.
static func _planks(c: PixelCanvas, base: Color, t: Dictionary, opts: Dictionary) -> Array[int]:
	var seams: Array[int] = []
	var along_x := c.w >= c.h
	var span := c.h if along_x else c.w
	var length := c.w if along_x else c.h
	var plank_px := maxi(3, int(opts.get("plank_px", ObjectArtConfig.table_plank_px)))
	var n := maxi(1, roundi(float(span) / plank_px))
	for i in n:
		var a := roundi(float(i) * span / n)
		var b := roundi(float(i + 1) * span / n)
		var r := Rect2i(0, a, length, b - a) if along_x else Rect2i(a, 0, b - a, length)
		var tone := _plank_face(c, base, r, along_x)
		if c.rng.randf() < ArtConfig.wood_knot_chance and b - a >= 4 and length >= 12:
			_knot(c, along_x, Rect2i(0, a, length, b - a), tone)
		if i > 0:
			_seam(c, along_x, a, length, t.shadow)
			seams.append(a)
		# A long plank is two boards end to end; neighbours stagger their joints.
		if length >= 50:
			_butt_joint(c, along_x, Rect2i(0, a, length, b - a), i, t.shadow)
	return seams


## One plank's face over `r` in a tone of `base` drawn per plank, with its grain (along x when
## `along_x`); returns the tone.
static func _plank_face(c: PixelCanvas, base: Color, r: Rect2i, along_x: bool) -> Color:
	var shift := c.rng.randf_range(-0.05, 0.05)
	var tone := base.lightened(shift) if shift > 0.0 else base.darkened(-shift)
	c.paint_over(r, tone)
	c.grain(PixelCanvas.rounded(r, 0), ArtConfig.wood_grain_density, tone.darkened(0.12),
			tone.lightened(0.06), { "along_x": along_x })
	return tone


## A knot in the plank `lane` (x along the planks, y across them) in a dark `tone`, somewhere along
## its middle.
static func _knot(c: PixelCanvas, along_x: bool, lane: Rect2i, tone: Color) -> void:
	var k_along := c.rng.randi_range(5, lane.size.x - 6)
	var k_across := int((lane.position.y + lane.end.y) / 2.0)
	var kp := Vector2i(k_along, k_across) if along_x else Vector2i(k_across, k_along)
	c.knot(kp.x, kp.y, tone.darkened(0.4), tone.darkened(0.2))


## The butt joint across the `i`-th plank `lane` (x along the planks, y across them) in `col`, a
## third or two thirds along by its parity so neighbours stagger (drawn pixels only).
static func _butt_joint(c: PixelCanvas, along_x: bool, lane: Rect2i, i: int, col: Color) -> void:
	var joint := roundi(lane.size.x * (0.3 if i % 2 == 0 else 0.65) + c.rng.randi_range(-4, 4))
	for j in range(lane.position.y + (1 if i > 0 else 0), lane.end.y):
		var jp := Vector2i(joint, j) if along_x else Vector2i(j, joint)
		if c.at(jp.x, jp.y).a > 0.0:
			c.px(jp.x, jp.y, col)


## A 1px seam line at `across` running 0..`to` along the planks (drawn pixels only).
static func _seam(c: PixelCanvas, along_x: bool, across: int, to: int, col: Color) -> void:
	for i in range(0, to):
		var p := Vector2i(i, across) if along_x else Vector2i(across, i)
		if c.at(p.x, p.y).a > 0.0:
			c.px(p.x, p.y, col)


## A recessed centre panel: a darker inlay with cross grain, framed by an inverted bevel (the
## edge nearest the light sits in shadow, the far edge catches light).
static func _inset(
	c: PixelCanvas,
	radius: int,
	base: Color,
	t: Dictionary,
	opts: Dictionary,
) -> void:
	var margin: int = opts.get("inset_margin", ObjectArtConfig.table_inset_margin)
	margin = mini(margin, int(mini(c.w, c.h) / 4.0))
	var inner_rect := Rect2i(0, 0, c.w, c.h).grow(-margin)
	if inner_rect.size.x < 4 or inner_rect.size.y < 4:
		return
	var inner := PixelCanvas.rounded(inner_rect, maxi(radius - 1, 1))
	var inlay := base.darkened(0.1)
	c.fill(inner, inlay)
	c.grain(
		inner,
		ArtConfig.wood_grain_density,
		inlay.darkened(0.12),
		inlay.lightened(0.05),
		{ "along_x": c.w >= c.h },
	)
	c.bevel(inner, 1, 1, t.shadow, t.light)
	c.bevel(inner, 2, 2, t.dark, inlay)


## A cloth runner down the long axis, hanging to the rim at both ends with a fringe, a border
## stripe along each edge and a woven diamond motif down its middle.
static func _runner(c: PixelCanvas) -> void:
	var along_x := c.w >= c.h
	var length := c.w if along_x else c.h
	var span := c.h if along_x else c.w
	var width := maxi(5, roundi(span * float(ObjectArtConfig.table_runner_width)))
	var a := int((span - width) / 2.0)
	var col := ObjectArtConfig.table_runner_color
	var r := Rect2i(1, a, length - 2, width) if along_x else Rect2i(a, 1, width, length - 2)
	c.fill(PixelCanvas.rounded(r, 0), col, _RUNNER_HEIGHT)
	c.speckle(r, col, ArtConfig.fabric_speckle)
	_runner_weave(c, along_x, Rect2i(0, a, length, width))


## The runner's weave over its `lane` (x along the runner, y across it): the border stripes, the
## diamonds down its middle and the fringe, every other thread at each end.
static func _runner_weave(c: PixelCanvas, along_x: bool, lane: Rect2i) -> void:
	var length := lane.size.x
	var a := lane.position.y
	var width := lane.size.y
	var mid := a + int(width / 2.0)
	var col := ObjectArtConfig.table_runner_color
	var rt := PixelCanvas.tones(col)
	var motif := maxi(2, int(width / 2.0) - 3)
	var period := motif * 2 + 2
	for i in range(1, length - 1):
		for s in [a, a + width - 1]:
			_dot(c, along_x, i, s, rt.dark)
		if width >= 9:
			for s in [a + 2, a + width - 3]:
				_dot(c, along_x, i, s, rt.light if i % 2 == 0 else col)
		# Diamonds: |offset from the motif centre along| + |offset across| == radius.
		var along_off := absi((i + int(period / 2.0)) % period - int(period / 2.0))
		if i > 3 and i < length - 4 and along_off <= motif:
			for s in [mid - (motif - along_off), mid + (motif - along_off)]:
				_dot(c, along_x, i, s, rt.shadow)
	# Fringe: every other thread at each end.
	for s in range(a, a + width):
		if s % 2 == 0:
			for end in [1, length - 2]:
				_dot(c, along_x, end, s, rt.light)


## Set one pixel addressed along/across the planks.
static func _dot(c: PixelCanvas, along_x: bool, along: int, across: int, col: Color) -> void:
	if along_x:
		c.px(along, across, col)
	else:
		c.px(across, along, col)
