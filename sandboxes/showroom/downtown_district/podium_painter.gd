extends RefCounted
## The podium band round a tower's ground floor: the lower, wider storeys' flat roof seen from
## above, a strip along the outside of an exterior wall (its front, +y, the street side). Options:
## `variant` `a` a thick concrete slab with pillars along its edge, `b` the slab with dark glass
## window strips set in it, `c` a dark slab with a neon trim strip along its edge.

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const SLAB := Color(0.47, 0.46, 0.42)
const DARK := Color(0.28, 0.28, 0.32)
const GLASS := Color(0.07, 0.11, 0.17)
const PILLAR_STEP := 48
const PILLAR := 16


## Paint the band of `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var variant := String(opts.get("variant", "a"))
	var base := DARK if variant == "c" else SLAB
	var all := Rect2i(0, 0, c.w, c.h)
	var shape := PixelShape.rounded(all, 0)
	c.fill(shape, base, 2)
	c.surface(shape, "stone", base)
	for x in range(PILLAR_STEP + 24, c.w, PILLAR_STEP * 2):
		Kit.fill_rect(c, Rect2i(x - 1, 0, 1, c.h), base.darkened(0.3))
	match variant:
		"b":
			_windows(c)
		"c":
			_neon(c)
		_:
			_pillars(c, base)
	c.bevel(shape, 1, 2, base.lightened(0.25), base.darkened(0.4))
	c.cast_shadows()
	Kit.grime(c, int(c.w * c.h / 300.0), 6, 0.22)
	Kit.rust(c, 6)


static func _pillars(c: PixelCanvas, base: Color) -> void:
	for x in range(6, c.w - PILLAR, PILLAR_STEP):
		Kit.block(c, Rect2i(x, c.h - PILLAR - 3, PILLAR, PILLAR), base.lightened(0.1), 14, 1)
		Kit.fill_rect(
			c,
			Rect2i(x + 4, c.h - PILLAR + 1, PILLAR - 8, PILLAR - 8),
			base.darkened(0.12),
		)


static func _windows(c: PixelCanvas) -> void:
	for x in range(8, c.w - 40, 54):
		var strip := Rect2i(x, 9, 42, 15)
		Kit.fill_rect(c, strip.grow(1), SLAB.darkened(0.45))
		Kit.fill_rect(c, strip, GLASS)
		for k in range(0, strip.size.x, 14):
			Kit.fill_rect(
				c,
				Rect2i(strip.position.x + k, strip.position.y, 1, strip.size.y),
				SLAB.darkened(0.3),
			)
		c.line(
			strip.position + Vector2i(4, strip.size.y - 3),
			strip.position + Vector2i(14, 3),
			Color(0.5, 0.62, 0.7),
		)
		c.line(
			strip.position + Vector2i(22, strip.size.y - 3),
			strip.position + Vector2i(30, 3),
			Color(0.4, 0.52, 0.6),
		)
	c.glowing(func() -> void:
		for x in [8, 116, 224]:
			Kit.fill_rect(c, Rect2i(x + 3, 12, 36, 9), Color(0.1, 0.32, 0.38))
	)


static func _neon(c: PixelCanvas) -> void:
	c.glowing(func() -> void:
		Kit.fill_rect(c, Rect2i(0, c.h - 6, c.w, 3), Kit.NEON_CYAN)
		for x in range(20, c.w, 60):
			Kit.fill_rect(c, Rect2i(x, c.h - 6, 14, 3), Kit.NEON_MAGENTA)
			Kit.fill_rect(c, Rect2i(x + 5, 6, 2, c.h - 12), Kit.NEON_MAGENTA)
	)
