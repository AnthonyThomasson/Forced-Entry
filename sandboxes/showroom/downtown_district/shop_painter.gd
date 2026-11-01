extends RefCounted
## The bodega's pieces, each in one of the three families (`opts.look`, `families.gd`): `kind`
## `counter` (a counter with a till, the customer side toward +y), `aisle` (a double-sided shelf
## aisle: a shelf run on each long side, the walkway between left clear), `fridge` (a glass-door
## drinks fridge, its lit glass along the front) and `snack` (a snack machine).

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const Families := preload("res://sandboxes/showroom/downtown_district/families.gd")
const PACKS: Array[Color] = [
	Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.9), Color(0.5, 0.85, 0.4),
	Color(0.9, 0.55, 0.15), Color(0.85, 0.85, 0.8),
]


## Paint the piece of `opts.kind` in the family of `opts.look` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var fam := Families.of(opts)
	match String(opts.get("kind", "counter")):
		"aisle":
			_aisle(c, fam)
		"fridge":
			_fridge(c, fam)
		"snack":
			_snack(c, fam)
		_:
			_counter(c, fam)


static func _counter(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 6, 2)
	var top := Rect2i(3, 3, c.w - 6, c.h - 11)
	Kit.block(c, top, fam["top"], 8, 1)
	c.surface(PixelShape.rounded(top, 1), "metal" if fam["dirt"] > 0.8 else "stone", fam["top"])
	Kit.fill_rect(c, Rect2i(3, c.h - 7, c.w - 6, 2), fam["accent"])
	var till := Rect2i(8, 7, 26, 17)
	Kit.block(c, till, (fam["body"] as Color).darkened(0.3), 12, 1)
	c.glowing(func() -> void:
		Kit.fill_rect(
			c,
			Rect2i(till.position.x + 3, till.position.y + 2, 20, 5),
			fam["glass"] if not Families.is_neon(fam) else fam["neon"],
		)
	)
	for k in 4:
		Kit.fill_rect(
			c,
			Rect2i(till.position.x + 4 + k * 5, till.position.y + 10, 3, 3),
			Color(0.78, 0.78, 0.74),
		)
	Kit.block(c, Rect2i(42, 9, 12, 10), Color(0.8, 0.78, 0.7), 9, 0)
	for k in 5:
		Kit.fill_rect(c, Rect2i(62 + k * 7, 8 + (k % 2) * 6, 5, 5), PACKS[k % PACKS.size()], 9)
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.fill_rect(c, Rect2i(4, c.h - 3, c.w - 8, 1), fam["neon2"]))
	c.cast_shadows()
	Families.finish(c, fam)


static func _aisle(c: PixelCanvas, fam: Dictionary) -> void:
	var depth := 20
	_shelf_run(c, fam, Rect2i(0, 0, c.w, depth), true)
	_shelf_run(c, fam, Rect2i(0, c.h - depth, c.w, depth), false)
	c.cast_shadows()
	Families.finish(c, fam)


## One shelf run of the aisle: two tiers of packs, a lit lip along the edge facing the walkway.
static func _shelf_run(c: PixelCanvas, fam: Dictionary, row: Rect2i, lit_edge: bool) -> void:
	Kit.block(c, row, fam["body"], 10, 1)
	for tier in 2:
		var y := row.position.y + 3 + tier * 8
		for x in range(3, c.w - 6, 6):
			var pack := PACKS[(int(x / 6.0) + tier + row.position.y) % PACKS.size()]
			Kit.fill_rect(c, Rect2i(x, y, 5, 6), pack.darkened(0.1 * float(fam["dirt"])), 12)
	var lip_y := row.end.y - 2 if lit_edge else row.position.y
	Kit.fill_rect(c, Rect2i(1, lip_y, c.w - 2, 2), fam["top"], 10)
	if Families.is_neon(fam):
		var neon_y := row.end.y - 1 if lit_edge else row.position.y
		c.glowing(func() -> void: Kit.fill_rect(c, Rect2i(1, neon_y, c.w - 2, 1), fam["neon"]))


static func _fridge(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 14, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 15), fam["top"], 14)
	for k in range(6, c.w - 6, 4):
		Kit.fill_rect(c, Rect2i(k, 5, 2, 5), (fam["body"] as Color).darkened(0.35))
	var glass := Rect2i(3, c.h - 11, c.w - 6, 8)
	Kit.fill_rect(c, glass.grow(1), (fam["body"] as Color).darkened(0.55))
	c.glowing(func() -> void:
		Kit.fill_rect(
			c,
			glass,
			Color(0.82, 0.95, 1.0) if not Families.is_neon(fam) else Color(0.5, 0.95, 1.0),
		)
		for k in range(0, glass.size.x - 3, 5):
			Kit.fill_rect(
				c,
				Rect2i(glass.position.x + 1 + k, glass.position.y + 1, 3, 6),
				PACKS[int(k / 5.0) % PACKS.size()],
			)
	)
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.frame(c, all.grow(-1), fam["neon2"]))
	c.cast_shadows()
	Families.finish(c, fam)


static func _snack(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 12, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 14), fam["top"], 12)
	Kit.fill_rect(c, Rect2i(c.w - 12, 5, 7, 8), Color(0.1, 0.1, 0.12), 12)
	for k in 6:
		Kit.fill_rect(
			c,
			Rect2i(c.w - 11 + (k % 2) * 3, 14 + int(k / 2.0) * 3, 2, 2),
			Color(0.8, 0.8, 0.76),
			12,
		)
	var window := Rect2i(3, c.h - 10, c.w - 6, 7)
	Kit.fill_rect(c, window.grow(1), (fam["body"] as Color).darkened(0.5))
	c.glowing(func() -> void:
		Kit.fill_rect(c, window, fam["glass"])
		for row in 2:
			for k in range(0, window.size.x - 3, 4):
				Kit.fill_rect(
					c,
					Rect2i(window.position.x + 1 + k, window.position.y + 1 + row * 3, 3, 2),
					PACKS[(int(k / 4.0) + row) % PACKS.size()],
				)
	)
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.frame(c, all.grow(-1), fam["neon2"]))
	c.cast_shadows()
	Families.finish(c, fam)
