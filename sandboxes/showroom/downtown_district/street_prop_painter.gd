extends RefCounted
## The sidewalk's clutter, each in one of the three families (`opts.look`, `families.gd`): `kind`
## `vending` (a drinks machine, its lit window toward the street, +y), `bench`, `bin` (a round bin),
## `grate` (a drain grate) and `litter` (flat scraps, no collider).

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const Families := preload("res://sandboxes/showroom/downtown_district/families.gd")
const PRODUCTS: Array[Color] = [
	Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.9), Color(0.5, 0.85, 0.4),
]


## Paint the piece of `opts.kind` in the family of `opts.look` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var fam := Families.of(opts)
	match String(opts.get("kind", "vending")):
		"bench":
			_bench(c, fam)
		"bin":
			_bin(c, fam)
		"grate":
			_grate(c, fam)
		"litter":
			_litter(c, fam)
		_:
			_vending(c, fam)


static func _vending(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 12, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 15), fam["top"])
	for k in range(5, c.w - 5, 5):
		Kit.fill_rect(c, Rect2i(k, 5, 1, c.h - 19), (fam["body"] as Color).darkened(0.2))
	var window := Rect2i(3, c.h - 10, c.w - 6, 7)
	Kit.fill_rect(c, window.grow(1), (fam["body"] as Color).darkened(0.5))
	c.glowing(func() -> void:
		Kit.fill_rect(c, window, fam["glass"])
		for k in range(0, window.size.x - 2, 4):
			Kit.fill_rect(
				c,
				Rect2i(window.position.x + 1 + k, window.position.y + 2, 3, 4),
				PRODUCTS[int(k / 4.0) % 4],
			)
	)
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.frame(c, all.grow(-1), fam["neon2"]))
	Families.finish(c, fam)


static func _bench(c: PixelCanvas, fam: Dictionary) -> void:
	for x in [3, c.w - 7]:
		Kit.block(c, Rect2i(x, 0, 4, c.h), fam["body"], 6, 0)
	var slats := 4
	var step := int((c.h - 2) / float(slats))
	for k in slats:
		var r := Rect2i(8, 1 + k * step, c.w - 16, step - 1)
		Kit.block(c, r, (fam["wood"] as Color).lightened(0.04 * (k % 2)), 4, 0)
		c.surface(PixelShape.rounded(r, 0), "wood", fam["wood"])
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.fill_rect(c, Rect2i(8, c.h - 2, c.w - 16, 1), fam["neon"]))
	Families.finish(c, fam)


static func _bin(c: PixelCanvas, fam: Dictionary) -> void:
	var mid := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(minf(c.w, c.h) / 2.0) - 1
	Kit.disc(c, mid, radius, (fam["body"] as Color).darkened(0.3), 10)
	Kit.disc(c, mid, radius - 2, fam["top"], 12)
	Kit.disc(c, mid + Vector2i(1, 1), radius - 6, Color(0.05, 0.05, 0.06), 12)
	c.outline(PixelShape.disc(mid, radius), (fam["body"] as Color).darkened(0.6))
	c.bevel(
		PixelShape.disc(mid, radius - 2),
		1,
		1,
		(fam["top"] as Color).lightened(0.3),
		(fam["body"] as Color).darkened(0.3),
	)
	if Families.is_neon(fam):
		c.glowing(func() -> void: c.outline(PixelShape.disc(mid, radius - 1), fam["neon"]))
	else:
		c.outline(PixelShape.disc(mid, radius - 3), (fam["accent"] as Color).darkened(0.2))
	Families.finish(c, fam)


static func _grate(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, (fam["body"] as Color).darkened(0.15), 1, 0)
	var inner := all.grow(-3)
	Kit.fill_rect(c, inner, Color(0.03, 0.03, 0.04))
	c.glowing(func() -> void:
		if Families.is_neon(fam):
			Kit.fill_rect(c, inner.grow(-1), Color(fam["neon"] as Color, 0.55))
	)
	for x in range(inner.position.x + 1, inner.end.x - 1, 4):
		Kit.block(c, Rect2i(x, inner.position.y, 2, inner.size.y), fam["top"], 1, 0)
	Families.finish(c, fam)


static func _litter(c: PixelCanvas, fam: Dictionary) -> void:
	var neon := Families.is_neon(fam)
	for _i in 9:
		var p := Vector2i(c.rng.randi_range(2, c.w - 6), c.rng.randi_range(2, c.h - 6))
		var col: Color = [
			fam["accent"],
			fam["top"],
			fam["wood"],
			PRODUCTS[c.rng.randi() % 4],
		][c.rng.randi() % 4]
		var size := Vector2i(c.rng.randi_range(2, 5), c.rng.randi_range(2, 4))
		if neon and c.rng.randf() < 0.4:
			c.glowing(func() -> void: Kit.fill_rect(c, Rect2i(p, size), fam["neon2"]))
		elif c.rng.randf() < 0.3:
			Kit.disc(c, p + Vector2i(2, 2), 2, col)
		else:
			Kit.fill_rect(c, Rect2i(p, size), col)
		c.px(p.x + size.x, p.y + size.y, Color(0, 0, 0, 0.35))
