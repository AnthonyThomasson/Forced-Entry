extends RefCounted
## A closed tower's roof seen from above, past the district's edge: a dark slab with a parapet
## round it and the machinery a roof carries. Options: `variant` `a` the slab, parapet and
## air-conditioning boxes (Glitchpunk), `b` also a water tank and vents, `c` also a rooftop neon
## billboard.

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const SLAB := Color(0.2, 0.2, 0.24)
const PARAPET := Color(0.36, 0.36, 0.4)
const UNIT := Color(0.46, 0.5, 0.52)
const WALL := 9


## Paint the roof of `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var variant := String(opts.get("variant", "a"))
	var all := Rect2i(0, 0, c.w, c.h)
	var shape := PixelShape.rounded(all, 0)
	c.fill(shape, PARAPET, 12)
	c.fill(PixelShape.rounded(all.grow(-WALL), 0), SLAB, 1)
	c.speckle(all.grow(-WALL), SLAB, 0.3, 0.05)
	_tar_patches(c, all.grow(-WALL))
	_units(c)
	_hutch(c)
	if variant == "b":
		_tank(c, Vector2i(c.w - 80, c.h - 76))
		_vents(c)
	if variant == "c":
		_billboard(c)
	c.bevel(shape, 1, 3, PARAPET.lightened(0.28), PARAPET.darkened(0.38))
	c.outline(shape, PARAPET.darkened(0.6))
	c.cast_shadows()
	Kit.grime(c, 28, 10, 0.2)


static func _tar_patches(c: PixelCanvas, area: Rect2i) -> void:
	for _i in 5:
		var r := Rect2i(
			area.position + Vector2i(
				c.rng.randi_range(0, area.size.x - 40),
				c.rng.randi_range(0, area.size.y - 30),
			),
			Vector2i(c.rng.randi_range(18, 40), c.rng.randi_range(10, 28)),
		)
		Kit.fill_rect(c, r, SLAB.darkened(0.25))


static func _units(c: PixelCanvas) -> void:
	for at in [Vector2i(24, c.h - 58), Vector2i(76, c.h - 58), Vector2i(24, 24)]:
		var r := Rect2i(at, Vector2i(40, 30))
		Kit.block(c, r, UNIT, 9, 2)
		for fan in [Vector2i(10, 15), Vector2i(29, 15)]:
			Kit.disc(c, at + fan, 8, Color(0.14, 0.15, 0.17), 9)
			Kit.disc(c, at + fan, 5, Color(0.22, 0.23, 0.26), 9)
			c.line(at + fan - Vector2i(5, 0), at + fan + Vector2i(5, 0), Color(0.4, 0.42, 0.46))
			c.line(at + fan - Vector2i(0, 5), at + fan + Vector2i(0, 5), Color(0.4, 0.42, 0.46))
		Kit.rust(c, 2)


## The stair hutch: a squat block over the stairwell with its door toward the south.
static func _hutch(c: PixelCanvas) -> void:
	var r := Rect2i(c.w - 76, 28, 44, 32)
	Kit.block(c, r, Color(0.3, 0.3, 0.34), 14, 1)
	Kit.fill_rect(c, Rect2i(r.position.x + 15, r.end.y - 5, 14, 5), Color(0.1, 0.1, 0.12), 14)
	Kit.frame(c, r.grow(-4), Color(0.22, 0.22, 0.26))


static func _tank(c: PixelCanvas, at: Vector2i) -> void:
	Kit.disc(c, at, 30, Color(0.1, 0.1, 0.12), 3)
	Kit.disc(c, at, 27, Color(0.5, 0.53, 0.56), 20)
	for r in [24, 19, 13]:
		var ring := PixelShape.disc(at, r)
		c.outline(ring, Color(0.34, 0.37, 0.4))
	Kit.disc(c, at, 6, Color(0.62, 0.64, 0.66), 22)
	c.line(at + Vector2i(-24, 12), at + Vector2i(-10, 22), Color(0.72, 0.74, 0.76))
	Kit.rust(c, 8)


static func _vents(c: PixelCanvas) -> void:
	for at in [Vector2i(c.w - 40, 30), Vector2i(c.w - 60, 48), Vector2i(130, 44)]:
		Kit.disc(c, at, 6, Color(0.5, 0.52, 0.55), 10)
		Kit.disc(c, at, 3, Color(0.2, 0.2, 0.23), 10)


static func _billboard(c: PixelCanvas) -> void:
	var board := Rect2i(int(c.w / 2.0) - 60, WALL + 2, 120, 22)
	Kit.block(c, board, Color(0.08, 0.08, 0.1), 16, 1)
	c.glowing(func() -> void:
		Kit.frame(c, board.grow(-1), Kit.NEON_MAGENTA)
		Glyphs.draw_centered(
			c,
			"RAMEN",
			int(c.w / 2.0),
			board.position.y + 4,
			Kit.ink(Kit.NEON_CYAN, 2),
		)
	)
	for x in [board.position.x + 4, board.end.x - 8]:
		Kit.fill_rect(c, Rect2i(x, board.end.y, 4, 8), Color(0.3, 0.3, 0.34), 8)
