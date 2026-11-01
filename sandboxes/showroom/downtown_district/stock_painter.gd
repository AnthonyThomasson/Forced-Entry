extends RefCounted
## The stockroom's pieces, each in one of the three families (`opts.look`, `families.gd`): `kind`
## `crates` (two crates stacked, the top one offset), `pallet` (a pallet with wrapped boxes) and
## `safe` (a wall safe: its top and the door's edge toward +y).

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const Families := preload("res://sandboxes/showroom/downtown_district/families.gd")
const CARDBOARD := Color(0.62, 0.48, 0.3)


## Paint the piece of `opts.kind` in the family of `opts.look` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var fam := Families.of(opts)
	match String(opts.get("kind", "crates")):
		"pallet":
			_pallet(c, fam)
		"safe":
			_safe(c, fam)
		_:
			_crates(c, fam)


static func _crate(c: PixelCanvas, r: Rect2i, fam: Dictionary, height: int) -> void:
	var base: Color = fam["wood"] if fam["dirt"] > 0.9 else fam["body"]
	if fam["dirt"] < 0.4:
		base = Color(0.42, 0.45, 0.3)
	Kit.block(c, r, base, height, 1)
	for k in range(r.position.y + 4, r.end.y - 3, 6):
		Kit.fill_rect(c, Rect2i(r.position.x + 2, k, r.size.x - 4, 1), base.darkened(0.3), height)
	c.line(r.position + Vector2i(3, 3), r.end - Vector2i(4, 4), base.darkened(0.25))
	c.line(
		Vector2i(r.end.x - 4, r.position.y + 3),
		Vector2i(r.position.x + 3, r.end.y - 4),
		base.darkened(0.25),
	)
	Kit.block(
		c,
		Rect2i(r.position + Vector2i(6, int(r.size.y / 2.0) - 4), Vector2i(r.size.x - 12, 9)),
		base.lightened(0.18),
		height + 1,
		0,
	)


static func _crates(c: PixelCanvas, fam: Dictionary) -> void:
	_crate(c, Rect2i(0, 8, 38, 38), fam, 8)
	_crate(c, Rect2i(8, 0, 38, 38), fam, 16)
	var label := Color(0.9, 0.88, 0.8)
	c.glowing(func() -> void:
		if Families.is_neon(fam):
			Kit.fill_rect(c, Rect2i(10, 33, 34, 2), fam["neon"])
			Kit.fill_rect(c, Rect2i(10, 4, 34, 1), fam["neon2"])
	)
	Glyphs.draw(
		c,
		"DRY",
		Vector2i(17, 16),
		Kit.ink(label if fam["dirt"] < 0.9 else label.darkened(0.3)),
	)
	c.cast_shadows()
	Families.finish(c, fam)


static func _pallet(c: PixelCanvas, fam: Dictionary) -> void:
	var base: Color = fam["wood"] if fam["dirt"] > 0.4 else Color(0.3, 0.42, 0.62)
	for y in range(0, c.h, 12):
		Kit.block(c, Rect2i(0, y, c.w, 9), base, 2, 0)
	var corners: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(c.w - 30, 2), Vector2i(2, c.h - 24), Vector2i(c.w - 30, c.h - 24),
	]
	for pos in corners:
		_wrapped_box(c, Rect2i(pos, Vector2i(28, 22)), fam)
	c.cast_shadows()
	Families.finish(c, fam)


## A box on the pallet under shrink wrap: a pale sheen and diagonal glints over it, a label on top.
static func _wrapped_box(c: PixelCanvas, r: Rect2i, fam: Dictionary) -> void:
	var box := CARDBOARD if fam["dirt"] > 0.4 else Color(0.86, 0.86, 0.82)
	if Families.is_neon(fam):
		box = Color(0.12, 0.12, 0.16)
	Kit.block(c, r, box, 10, 1)
	Kit.over_rect(c, r.grow(-1), Color(0.9, 0.94, 1.0, 0.14))
	for k in range(-r.size.y, r.size.x, 9):
		var from := r.position + Vector2i(k, r.size.y - 1)
		c.line(from, from + Vector2i(r.size.y - 1, 1 - r.size.y), Color(1, 1, 1, 0.22))
	Kit.fill_rect(
		c,
		Rect2i(r.position + Vector2i(9, 8), Vector2i(10, 6)),
		Color(0.92, 0.9, 0.84),
		11,
	)
	if Families.is_neon(fam):
		var strip := Rect2i(r.position + Vector2i(3, r.size.y - 4), Vector2i(22, 1))
		c.glowing(func() -> void: Kit.fill_rect(c, strip, fam["neon"]))


static func _safe(c: PixelCanvas, fam: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.block(c, all, fam["body"], 10, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 11), fam["top"], 10)
	var door := Rect2i(3, c.h - 8, c.w - 6, 5)
	Kit.block(c, door, (fam["body"] as Color).lightened(0.05), 6, 0)
	Kit.disc(c, Vector2i(10, c.h - 6), 2, Color(0.85, 0.85, 0.8))
	Kit.fill_rect(c, Rect2i(c.w - 12, c.h - 7, 7, 3), Color(0.06, 0.06, 0.08))
	c.glowing(func() -> void:
		if Families.is_neon(fam):
			Kit.fill_rect(c, Rect2i(c.w - 11, c.h - 7, 5, 1), fam["neon"])
			Kit.frame(c, all.grow(-1), fam["neon2"])
	)
	for x in [4, c.w - 6]:
		Kit.disc(c, Vector2i(x, 5), 1, Color(0.2, 0.2, 0.22))
	c.cast_shadows()
	Families.finish(c, fam)
