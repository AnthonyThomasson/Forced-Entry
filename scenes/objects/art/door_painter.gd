extends RefCounted
## Top-down pixel-art DOOR painter (Objects domain, private), in the run-down look. `opts`:
##  - `part`: `leaf` (default), the standing leaf seen from above, `x` along it from the hinge to
##    the latch and `y` across its thickness: the stiles, rails, planks, rivets or panes along its
##    top edge, a hinge pin at one end and the handle at the other. A knocked-down door is the same
##    leaf, lying (`docs/doors.md` DR11).
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
	var style := String(opts.get("style", "flush"))
	var kind := String(opts.get("door_material", "hollow"))
	var broken := bool(opts.get("broken", false))
	var t := ArtSurfaceConfig.tones(base)
	var slab := PixelShape.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(slab, base, _LEAF)
	c.surface(slab, material, base, true)
	match style:
		"panelled":
			_panelled(c, base)
		"plank":
			_planks(c, base)
		"riveted":
			_riveted(c, base)
		"peephole":
			_peephole(c, base)
		"panes":
			_panes(c, broken)
	c.bevel(slab, 1, 1, t["highlight"], t["shadow"])
	_hardware(c)
	if kind == "steel":
		Decay.rust(c, ObjectArtDoorConfig.steel_rust)
	else:
		Decay.scratches(c, ObjectArtDoorConfig.wood_scratches)
	Decay.grime(c, -1.0, 3)


## The stiles and the middle rail across a leaf's top.
static func _panelled(c: PixelCanvas, base: Color) -> void:
	var dark := base.darkened(ObjectArtDoorConfig.panel_darken)
	for x in [int(c.w / 4.0), int(c.w / 2.0), int(c.w * 3 / 4.0)]:
		c.line(Vector2i(x, 1), Vector2i(x, c.h - 2), dark, _LEAF)


## Boards running the leaf's height: a seam every `plank_px`, boards of their own tone.
static func _planks(c: PixelCanvas, base: Color) -> void:
	var step := ObjectArtDoorConfig.plank_px
	var seam := base.darkened(0.32)
	for k in range(1, int(c.w / float(step)) + 1):
		var at := k * step
		if at >= c.w:
			break
		c.speckle(Rect2i(at - step, 0, step, c.h), base, 0.5, 0.1)
		c.line(Vector2i(at, 0), Vector2i(at, c.h - 1), seam, _LEAF)


## A steel leaf with rivets along its top edge.
static func _riveted(c: PixelCanvas, _base: Color) -> void:
	var step := ObjectArtDoorConfig.rivet_px
	var rivet := ObjectArtDoorConfig.fitting_color.lightened(0.25)
	for x in range(2, c.w - 1, step):
		c.px(x, 1, rivet, _RAISED)
		c.px(x, c.h - 2, rivet, _RAISED)


## A plain steel leaf with the peephole's lens near the middle, ringed pale.
static func _peephole(c: PixelCanvas, base: Color) -> void:
	var at := Vector2i(int(c.w * 0.3), int(c.h / 2.0))
	c.fill(PixelShape.rounded(Rect2i(at.x - 1, 1, 3, c.h - 2), 0), base.darkened(0.6), _LEAF)
	c.px(at.x, at.y, ObjectArtDoorConfig.glass_glare, _RAISED)


## A wooden frame holding the panes: glass between rails along a leaf's top. Shattered, the glass is
## gone but for a few shards left in the corners.
static func _panes(c: PixelCanvas, broken: bool) -> void:
	var cell := ObjectArtDoorConfig.pane_px
	var frame := 4
	var area := Rect2i(frame, 1, c.w - 2 * frame, c.h - 2)
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


## The hinge (a pin at the hinge end of a leaf) and the handle (not on a flat leaf: the 3D door has
## its own).
static func _hardware(c: PixelCanvas) -> void:
	var metal := ObjectArtDoorConfig.fitting_color
	var handle := ObjectArtDoorConfig.handle_color
	c.fill(PixelShape.rounded(Rect2i(0, 1, 3, c.h - 2), 0), metal, _RAISED)
	if c.light == Vector2.ZERO:
		return  # Flat (the 3D leaf): the handle is a mesh of its own, off the leaf's face.
	c.fill(PixelShape.rounded(Rect2i(c.w - 7, 1, 5, c.h - 2), 0), handle, _RAISED)
	c.px(c.w - 6, int(c.h / 2.0), handle.lightened(0.3), _RAISED)
