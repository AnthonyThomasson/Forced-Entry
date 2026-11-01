extends RefCounted
## The noodle bar's pieces, each in one of the three families (`opts.look`, `families.gd`): `kind`
## `bar` (a long counter with steaming pots and bowls, the diners' side toward +y), `stool` (a round
## bar stool), `booth` (two benches and a table between them) and `menu` (a neon menu board).

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const Families := preload("res://sandboxes/showroom/downtown_district/families.gd")
const BROTH := Color(0.74, 0.5, 0.2)
const BOWL := Color(0.9, 0.88, 0.8)


## Paint the piece of `opts.kind` in the family of `opts.look` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var fam := Families.of(opts)
	match String(opts.get("kind", "bar")):
		"stool":
			_stool(c, fam)
		"booth":
			_booth(c, fam)
		"menu":
			_menu(c, fam)
		_:
			_bar(c, fam)


static func _bar(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 6, 2)
	var top := Rect2i(3, 3, c.w - 6, c.h - 9)
	Kit.block(c, top, fam["top"], 8, 1)
	c.surface(
		PixelShape.rounded(top, 1),
		"wood" if fam["dirt"] < 0.6 or fam["dirt"] > 0.9 else "metal",
		fam["top"],
	)
	Kit.fill_rect(c, Rect2i(3, c.h - 6, c.w - 6, 2), fam["accent"])
	for x in [18, 52, 86]:
		Kit.disc(c, Vector2i(x, 12), 8, (fam["body"] as Color).darkened(0.4), 12)
		Kit.disc(c, Vector2i(x, 12), 6, Color(0.55, 0.56, 0.58), 13)
		Kit.disc(c, Vector2i(x, 12), 4, BROTH.darkened(0.2), 13)
	for x in [112, 124, 136]:
		Kit.disc(c, Vector2i(x, 20), 5, BOWL, 9)
		Kit.disc(c, Vector2i(x, 20), 3, BROTH, 9)
	c.line(Vector2i(104, 8), Vector2i(104, 18), Color(0.6, 0.6, 0.58), 10)
	if Families.is_neon(fam):
		c.glowing(func() -> void:
			Kit.fill_rect(c, Rect2i(4, c.h - 3, c.w - 8, 1), fam["neon"])
			Kit.fill_rect(c, Rect2i(4, 4, c.w - 8, 1), fam["neon2"])
		)
	c.cast_shadows()
	Families.finish(c, fam)


static func _stool(c: PixelCanvas, fam: Dictionary) -> void:
	var mid := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(c.w / 2.0) - 1
	Kit.disc(c, mid, radius, (fam["body"] as Color).darkened(0.3), 5)
	Kit.disc(c, mid, radius - 2, fam["wood"] if fam["dirt"] > 0.9 else fam["top"], 6)
	c.outline(PixelShape.disc(mid, radius), (fam["body"] as Color).darkened(0.6))
	c.bevel(
		PixelShape.disc(mid, radius - 2),
		1,
		1,
		(fam["top"] as Color).lightened(0.3),
		(fam["body"] as Color).darkened(0.4),
	)
	Kit.disc(c, mid, 2, (fam["body"] as Color).darkened(0.4), 6)
	if Families.is_neon(fam):
		c.glowing(func() -> void: c.outline(PixelShape.disc(mid, radius - 1), fam["neon2"]))
	Families.finish(c, fam)


static func _booth(c: PixelCanvas, fam: Dictionary) -> void:
	for y in [0, c.h - 18]:
		var seat := Rect2i(0, y, c.w, 18)
		Kit.block(c, seat, fam["body"], 5, 3)
		for x in range(8, c.w - 4, 16):
			Kit.fill_rect(c, Rect2i(x, y + 3, 1, 12), (fam["body"] as Color).darkened(0.3))
	var table := Rect2i(8, 22, c.w - 16, c.h - 44)
	Kit.block(c, table, fam["top"], 8, 1)
	c.surface(PixelShape.rounded(table, 1), "wood", fam["top"])
	for x in [30, 70]:
		Kit.disc(c, Vector2i(x, int(c.h / 2.0)), 6, BOWL, 10)
		Kit.disc(c, Vector2i(x, int(c.h / 2.0)), 4, BROTH, 10)
		c.line(
			Vector2i(x + 8, int(c.h / 2.0) - 4),
			Vector2i(x + 8, int(c.h / 2.0) + 4),
			fam["accent"],
			10,
		)
	if Families.is_neon(fam):
		c.glowing(func() -> void: Kit.frame(c, table, fam["neon"]))
	c.cast_shadows()
	Families.finish(c, fam)


static func _menu(c: PixelCanvas, fam: Dictionary) -> void:
	var board := Rect2i(2, 0, c.w - 4, c.h)
	Kit.block(c, board, (fam["body"] as Color).darkened(0.35), 14, 1)
	var neon: Color = fam["neon"] if Families.is_neon(fam) else fam["accent"]
	var neon2: Color = fam["neon2"] if Families.is_neon(fam) else Color(0.95, 0.85, 0.5)
	c.glowing(func() -> void:
		Glyphs.draw(c, "RAMEN", Vector2i(8, 2), Kit.ink(neon))
		Glyphs.draw(c, "UDON", Vector2i(8, 10), Kit.ink(neon2.darkened(0.1)))
		Glyphs.draw_hanzi(c, "大", Vector2i(c.w - 44, 3), 10, Kit.ink(neon2))
		Glyphs.draw_hanzi(c, "中", Vector2i(c.w - 30, 3), 10, Kit.ink(neon2))
		Glyphs.draw_hanzi(c, "王", Vector2i(c.w - 16, 3), 10, Kit.ink(neon2))
		Kit.fill_rect(c, Rect2i(46, 7, 12, 1), neon)
		Kit.fill_rect(c, Rect2i(46, 15, 12, 1), neon2)
		Kit.frame(c, board.grow(-1), neon.darkened(0.2))
	)
	Families.finish(c, fam)
