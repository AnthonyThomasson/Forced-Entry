extends RefCounted
## The loose things in a roofless shell tower's bare interior, seen from above and lying on the
## floor to be walked over. Options: `kind` `rebar` (a bundle of steel rods tied in two places),
## `rubble` (a pile of broken concrete), `scaffold` (steel tubes and boards laid out in a frame),
## `cement` (a stack of grey paper bags) or `stain` (damp running down a wall: dark streaks that
## start along the top edge, y = 0, where the wall is, and run toward +y).

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const STEEL := Color(0.44, 0.34, 0.28)
const CONCRETE := Color(0.5, 0.5, 0.52)
const TUBE := Color(0.6, 0.62, 0.66)
const BOARD := Color(0.56, 0.44, 0.28)
const BAG := Color(0.62, 0.6, 0.55)
const DAMP := Color(0.08, 0.1, 0.12)


## Paint the `opts.kind` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "rubble")):
		"rebar":
			_rebar(c)
		"scaffold":
			_scaffold(c)
		"cement":
			_cement(c)
		"stain":
			_stain(c)
		_:
			_rubble(c)


static func _rebar(c: PixelCanvas) -> void:
	for y in range(1, c.h - 2, 4):
		var shade := STEEL.lightened(c.rng.randf_range(-0.1, 0.1))
		var run := Rect2i(c.rng.randi_range(0, 3), y, c.w - c.rng.randi_range(0, 6) - 3, 2)
		Kit.fill_rect(c, run, shade, 3)
		c.line(Vector2i(run.position.x, y), Vector2i(run.end.x - 1, y), shade.lightened(0.35))
	for x in [int(c.w * 0.3), int(c.w * 0.72)]:
		Kit.fill_rect(c, Rect2i(x, 0, 2, c.h), Color(0.1, 0.1, 0.12), 5)
	Kit.rust(c, 14)
	c.cast_shadows()


static func _rubble(c: PixelCanvas) -> void:
	var middle := Vector2(c.w * 0.5, c.h * 0.5)
	for _i in int(c.w * c.h / 90.0):
		var at := Vector2i(
			middle + Vector2(
				c.rng.randfn(0.0, c.w * 0.2),
				c.rng.randfn(0.0, c.h * 0.2),
			),
		)
		var chunk := Rect2i(at, Vector2i(c.rng.randi_range(4, 11), c.rng.randi_range(3, 8)))
		if Rect2i(1, 1, c.w - 2, c.h - 2).encloses(chunk):
			var tone := CONCRETE.lightened(c.rng.randf_range(-0.3, 0.25))
			Kit.block(c, chunk, tone, c.rng.randi_range(2, 6), 1)
	Kit.grime(c, 5, 6, 0.18)
	c.cast_shadows()


static func _scaffold(c: PixelCanvas) -> void:
	var inner := Rect2i(0, 0, c.w, c.h)
	for y in range(3, c.h - 3, 12):
		Kit.fill_rect(c, Rect2i(0, y, c.w, 9), BOARD.darkened(c.rng.randf_range(0.0, 0.2)), 2)
		c.line(Vector2i(0, y + 4), Vector2i(c.w - 1, y + 4), BOARD.darkened(0.4))
	for x in [1, int(c.w / 2.0), c.w - 4]:
		Kit.fill_rect(c, Rect2i(x, 0, 3, c.h), TUBE, 8)
		c.line(Vector2i(x + 1, 0), Vector2i(x + 1, c.h - 1), TUBE.lightened(0.3))
	for x in range(0, c.w - 20, 40):
		c.line(Vector2i(x, 0), Vector2i(x + 20, c.h - 1), TUBE.darkened(0.2))
	Kit.frame(c, inner, TUBE.darkened(0.45))
	Kit.rust(c, 6)
	c.cast_shadows()


static func _cement(c: PixelCanvas) -> void:
	var bags := 2 + int(c.w / 40.0)
	for i in bags:
		var r := Rect2i(
			c.rng.randi_range(0, maxi(0, c.w - 26)),
			c.rng.randi_range(0, maxi(0, c.h - 16)),
			24,
			15,
		)
		var tone := BAG.darkened(c.rng.randf_range(0.0, 0.18))
		Kit.block(c, r, tone, 4 + i % 3, 3)
		c.line(
			r.position + Vector2i(3, 5),
			r.position + Vector2i(r.size.x - 4, 5),
			tone.darkened(0.3),
		)
		Kit.fill_rect(c, Rect2i(r.position + Vector2i(7, 8), Vector2i(9, 3)), Color(0.7, 0.2, 0.16))
	Kit.grime(c, 3, 5, 0.16)
	c.cast_shadows()


static func _stain(c: PixelCanvas) -> void:
	for x in range(2, c.w - 2, 3):
		var length := int(c.h * c.rng.randf_range(0.25, 1.0) * (1.0 - absf(x - c.w * 0.5) / c.w))
		for y in length:
			var fade := 1.0 - float(y) / maxf(1.0, length)
			Kit.over(c, x, y, Color(DAMP.r, DAMP.g, DAMP.b, 0.8 * fade))
			Kit.over(c, x + 1, y, Color(DAMP.r, DAMP.g, DAMP.b, 0.45 * fade))
