extends RefCounted
## The tower's upper floors drawn overhead, over the ground floor's footprint and a little past it.
## Options: `variant` `a` a semi-transparent dark slab, `b` a parapet edge outline only (the middle
## left open), `c` the slab with a grid of windows, a few lit.

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const SLAB := Color(0.1, 0.11, 0.16, 0.62)
const EDGE := Color(0.3, 0.32, 0.4)
const COPING := 10
const WINDOW := Vector2i(14, 10)
const GAP := Vector2i(10, 12)


## Paint the overhang of `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	match String(opts.get("variant", "a")):
		"b":
			_parapet(c, all)
		"c":
			_slab(c, all)
			_windows(c, all.grow(-COPING - 6))
			_coping(c, all, 0.7)
		_:
			_slab(c, all)
			_coping(c, all, 0.7)


static func _slab(c: PixelCanvas, all: Rect2i) -> void:
	Kit.fill_rect(c, all, SLAB)
	Kit.grime(c, int(c.w * c.h / 600.0), 9, 0.3)


## The slab's rim: the edge facing the light lit, the far edges dark, `alpha` of the way opaque.
static func _coping(c: PixelCanvas, all: Rect2i, alpha: float) -> void:
	var rim := Color(EDGE, alpha)
	for k in COPING:
		var lit := k < 3
		var col := rim.lightened(0.18) if lit else rim.darkened(0.1 + 0.03 * k)
		var r := all.grow(-k)
		Kit.frame(c, r, Color(col, alpha) if k < COPING - 2 else Color(0.04, 0.04, 0.07, alpha))


static func _parapet(c: PixelCanvas, all: Rect2i) -> void:
	_coping(c, all, 0.92)
	for k in range(COPING, COPING + 3):
		Kit.frame(c, all.grow(-k), Color(0.03, 0.03, 0.06, 0.45 - 0.12 * (k - COPING)))
	for corner in [all.position, Vector2i(all.end.x - 16, all.position.y),
			Vector2i(all.position.x, all.end.y - 16), all.end - Vector2i(16, 16)]:
		Kit.fill_rect(c, Rect2i(corner, Vector2i(16, 16)), Color(0.38, 0.4, 0.48, 0.95))
		Kit.frame(c, Rect2i(corner, Vector2i(16, 16)), Color(0.04, 0.04, 0.07, 0.95))


static func _windows(c: PixelCanvas, area: Rect2i) -> void:
	var lit: Array[Rect2i] = []
	for y in range(area.position.y, area.end.y - WINDOW.y, WINDOW.y + GAP.y):
		for x in range(area.position.x, area.end.x - WINDOW.x, WINDOW.x + GAP.x):
			var r := Rect2i(Vector2i(x, y), WINDOW)
			Kit.fill_rect(c, r, Color(0.04, 0.06, 0.1, 0.92))
			Kit.fill_rect(c, Rect2i(r.position, Vector2i(r.size.x, 1)), Color(0.4, 0.5, 0.6, 0.6))
			if c.rng.randf() < 0.18:
				lit.append(r)
	c.glowing(func() -> void:
		for r in lit:
			var col := Kit.NEON_AMBER if c.rng.randf() < 0.7 else Kit.NEON_CYAN
			Kit.fill_rect(c, r.grow(-1), Color(col, 0.85))
	)
