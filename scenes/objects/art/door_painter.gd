extends RefCounted
## Top-down pixel-art DOOR painter (Objects domain, private), in the run-down look. `opts`:
##  - `part`: `leaf` (default), the standing leaf seen from above, `x` along it from the hinge to
##    the latch and `y` across its thickness: the stiles, rails, planks, rivets or panes along its
##    top edge, a hinge pin at one end and the handle at the other; or `fallen`, the knocked-down
##    door lying face up, `x` along its length and the hinge edge at `y` 0: panels, planks, rivets,
##    a peephole or the pane grid, three hinge plates and the handle.
##  - `style`: `flush`, `panelled`, `plank`, `riveted`, `peephole` or `panes`.
##  - `door_material`: `hollow`, `solid`, `steel` or `glass` (a steel leaf rusts, a wooden one is
##    scratched; the glass door's panes are glass between wooden rails).
##  - `broken`: the glass panes have shattered, leaving the frame and a few shards.
## `base` is the leaf's colour (the frame's, for a glass door) and `material` its surface finish
## (`wood`, `metal`). Knobs: ObjectArtDoorConfig.

const Decay = preload("res://scenes/objects/art/decay.gd")
## Heights for cast shadows, floor-up.
const _LEAF := 4
const _RAISED := 5


## Paint a door onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var fallen := String(opts.get("part", "leaf")) == "fallen"
	var style := String(opts.get("style", "flush"))
	var kind := String(opts.get("door_material", "hollow"))
	var broken := bool(opts.get("broken", false))
	var t := ArtSurfaceConfig.tones(base)
	var slab := PixelShape.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(slab, base, _LEAF)
	c.surface(slab, material, base, true)
	match style:
		"panelled":
			_panelled(c, base, fallen)
		"plank":
			_planks(c, base, fallen)
		"riveted":
			_riveted(c, base, fallen)
		"peephole":
			_peephole(c, base, fallen)
		"panes":
			_panes(c, fallen, broken)
	c.bevel(slab, 1, 1, t["highlight"], t["shadow"])
	_hardware(c, fallen)
	if kind == "steel":
		Decay.rust(c, ObjectArtDoorConfig.steel_rust)
	else:
		Decay.scratches(c, ObjectArtDoorConfig.wood_scratches)
	Decay.grime(c, -1.0, 3)


## Two recessed panels on a face, or the stiles and the middle rail across a leaf's top.
static func _panelled(c: PixelCanvas, base: Color, fallen: bool) -> void:
	var dark := base.darkened(ObjectArtDoorConfig.panel_darken)
	if fallen:
		var half := int(c.w / 2.0)
		for x0 in [6, half + 3]:
			var panel := PixelShape.rounded(Rect2i(x0, 6, half - 9, c.h - 12), 0)
			c.fill(panel, dark, _LEAF)
			c.bevel(panel, 1, 1, base.darkened(0.35), base.lightened(0.12))
		return
	for x in [int(c.w / 4.0), int(c.w / 2.0), int(c.w * 3 / 4.0)]:
		c.line(Vector2i(x, 1), Vector2i(x, c.h - 2), dark, _LEAF)


## Boards running the leaf's height: a seam every `plank_px`, boards of their own tone.
static func _planks(c: PixelCanvas, base: Color, fallen: bool) -> void:
	var step := ObjectArtDoorConfig.plank_px
	var seam := base.darkened(0.32)
	var limit := c.h if fallen else c.w
	for k in range(1, int(limit / float(step)) + 1):
		var at := k * step
		if at >= limit:
			break
		var board := Rect2i(0, at - step, c.w, step) if fallen else Rect2i(at - step, 0, step, c.h)
		c.speckle(board, base, 0.5, 0.1)
		if fallen:
			c.line(Vector2i(0, at), Vector2i(c.w - 1, at), seam, _LEAF)
		else:
			c.line(Vector2i(at, 0), Vector2i(at, c.h - 1), seam, _LEAF)


## A steel leaf with rivets along its edges, and on a face a seam at each third.
static func _riveted(c: PixelCanvas, base: Color, fallen: bool) -> void:
	var step := ObjectArtDoorConfig.rivet_px
	var rivet := ObjectArtDoorConfig.fitting_color.lightened(0.25)
	if fallen:
		for x in range(3, c.w - 2, step):
			c.px(x, 3, rivet, _RAISED)
			c.px(x, c.h - 4, rivet, _RAISED)
		for y in range(3 + step, c.h - 3, step):
			c.px(3, y, rivet, _RAISED)
			c.px(c.w - 4, y, rivet, _RAISED)
		for x in [int(c.w / 3.0), int(c.w * 2 / 3.0)]:
			c.line(Vector2i(x, 4), Vector2i(x, c.h - 5), base.darkened(0.3), _LEAF)
		return
	for x in range(2, c.w - 1, step):
		c.px(x, 1, rivet, _RAISED)
		c.px(x, c.h - 2, rivet, _RAISED)


## A plain steel leaf with the peephole's lens near the middle, ringed pale.
static func _peephole(c: PixelCanvas, base: Color, fallen: bool) -> void:
	var at := Vector2i(int(c.w * 0.3), int(c.h / 2.0))
	if fallen:
		var ring := PixelShape.disc(at, 3)
		c.fill(ring, ObjectArtDoorConfig.fitting_color.lightened(0.2), _RAISED)
		c.fill(PixelShape.disc(at, 1), base.darkened(0.7), _RAISED)
		return
	c.fill(PixelShape.rounded(Rect2i(at.x - 1, 1, 3, c.h - 2), 0), base.darkened(0.6), _LEAF)
	c.px(at.x, at.y, ObjectArtDoorConfig.glass_glare, _RAISED)


## A wooden frame holding the panes: glass between rails along a leaf's top, a grid of panes in the
## frame on a face. Shattered, the glass is gone but for a few shards left in the corners.
static func _panes(c: PixelCanvas, fallen: bool, broken: bool) -> void:
	var cell := ObjectArtDoorConfig.pane_px
	var frame := 4 if not fallen else 6
	var area := (Rect2i(frame, 1, c.w - 2 * frame, c.h - 2) if not fallen
			else Rect2i(frame, frame, c.w - 2 * frame, c.h - 2 * frame))
	var columns := maxi(1, int(area.size.x / float(cell)))
	var width := int(area.size.x / float(columns))
	for k in columns:
		var rect := Rect2i(area.position.x + k * width, area.position.y, width - 1, area.size.y)
		if k == columns - 1:
			rect.size.x = area.end.x - rect.position.x
		var pane := PixelShape.rounded(rect, 0)
		if broken:
			c.fill(pane, PixelCanvas.CLEAR, 0)
			_shards(c, rect)
		else:
			c.fill(pane, ObjectArtDoorConfig.glass_color, _LEAF)
			c.glare(pane, ObjectArtDoorConfig.glass_glare, 1)


## A few glass slivers left at the corners of an emptied pane `rect`.
static func _shards(c: PixelCanvas, rect: Rect2i) -> void:
	var glint := ObjectArtDoorConfig.glass_glare
	for corner in [rect.position, Vector2i(rect.end.x - 1, rect.position.y),
			Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]:
		var inward := Vector2i(1 if corner.x == rect.position.x else -1,
				1 if corner.y == rect.position.y else -1)
		c.px(corner.x, corner.y, glint, _RAISED)
		if c.rng.randf() < 0.7:
			c.px(corner.x + inward.x, corner.y, glint, _RAISED)
		if c.rng.randf() < 0.4 and rect.size.y > 3:
			c.px(corner.x, corner.y + inward.y, glint, _RAISED)


## The hinge (a pin at the hinge end of a leaf, three plates on a face's hinge edge) and the handle.
static func _hardware(c: PixelCanvas, fallen: bool) -> void:
	var metal := ObjectArtDoorConfig.fitting_color
	var handle := ObjectArtDoorConfig.handle_color
	if fallen:
		for x in [10, int(c.w / 2.0), c.w - 11]:
			c.fill(PixelShape.rounded(Rect2i(x - 2, 0, 4, 4), 0), metal, _RAISED)
		var at := Vector2i(int(c.w * 0.5), c.h - 9)
		c.fill(PixelShape.rounded(Rect2i(at.x - 2, at.y - 1, 5, 6), 0), metal, _RAISED)
		c.fill(PixelShape.rounded(Rect2i(at.x - 1, at.y, 8, 2), 0), handle, _RAISED)
		return
	c.fill(PixelShape.rounded(Rect2i(0, 1, 3, c.h - 2), 0), metal, _RAISED)
	c.fill(PixelShape.rounded(Rect2i(c.w - 7, 1, 5, c.h - 2), 0), handle, _RAISED)
	c.px(c.w - 6, int(c.h / 2.0), handle.lightened(0.3), _RAISED)
