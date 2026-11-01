extends RefCounted
## Top-down pixel-art STOCKROOM painter (Objects domain, private): the tower stockroom's pieces,
## `kind` in the options.
##   `crates`: two wooden crates stacked, the top one offset, a stencilled label;
##   `pallet`: a wooden pallet with four shrink-wrapped boxes;
##   `safe`: a wall safe in grimy steel, its top and the door's edge toward +y.
## Canonical frame: the front toward +y; the catalogue colour is the steel (the safe's). Knobs:
## ObjectArtShopConfig.stock_*. Run down (decay.gd): grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Glyphs = preload("res://scenes/objects/art/glyphs.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")


## Paint the stockroom piece `opts.kind` onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "crates")):
		"pallet":
			_pallet(c, opts)
		"safe":
			_safe(c, base)
		_:
			_crates(c, opts)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(1, int(c.w * c.h / 300.0)))


## One crate of `wood` in `r`: slats, a cross brace and a plate, `height` tall.
static func _crate(c: PixelCanvas, r: Rect2i, wood: Color, height: int) -> void:
	Tech.box(c, r, wood, height, 1)
	for k in range(r.position.y + 4, r.end.y - 3, 6):
		Kit.fill_rect(c, Rect2i(r.position.x + 2, k, r.size.x - 4, 1), wood.darkened(0.3), height)
	c.line(r.position + Vector2i(3, 3), r.end - Vector2i(4, 4), wood.darkened(0.25))
	c.line(Vector2i(r.end.x - 4, r.position.y + 3), Vector2i(r.position.x + 3, r.end.y - 4),
			wood.darkened(0.25))
	var plate := Rect2i(
		r.position + Vector2i(6, int(r.size.y / 2.0) - 4),
		Vector2i(r.size.x - 12, 9),
	)
	Tech.box(c, plate, wood.lightened(0.18), height + 1, 0)


## Two crates, the top one offset, with a stencilled label.
static func _crates(c: PixelCanvas, opts: Dictionary) -> void:
	var wood: Color = opts.get("wood_color", ObjectArtShopConfig.stock_wood_color)
	var label: Color = opts.get("label_color", ObjectArtShopConfig.stock_label_color)
	_crate(c, Rect2i(0, 8, 38, 38), wood, 8)
	_crate(c, Rect2i(8, 0, 38, 38), wood, 16)
	Glyphs.draw(c, "DRY", Vector2i(17, 16), Kit.ink(label.darkened(0.3)))


## A wooden pallet with four wrapped boxes.
static func _pallet(c: PixelCanvas, opts: Dictionary) -> void:
	var wood: Color = opts.get("wood_color", ObjectArtShopConfig.stock_wood_color)
	for y in range(0, c.h, 12):
		Tech.box(c, Rect2i(0, y, c.w, 9), wood, 2, 0)
	var corners: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(c.w - 30, 2), Vector2i(2, c.h - 24), Vector2i(c.w - 30, c.h - 24),
	]
	for pos in corners:
		_wrapped_box(c, Rect2i(pos, Vector2i(28, 22)), opts)


## A box on the pallet under shrink wrap: a pale sheen and glints over it, a label on top.
static func _wrapped_box(c: PixelCanvas, r: Rect2i, opts: Dictionary) -> void:
	var box: Color = opts.get("cardboard_color", ObjectArtShopConfig.stock_cardboard_color)
	Tech.box(c, r, box, 10, 1)
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


## A safe: a steel body, a lighter top, the door's edge with its dial and handle.
static func _safe(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, 10, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 11), base.lightened(0.1), 10)
	Tech.box(c, Rect2i(3, c.h - 8, c.w - 6, 5), base.lightened(0.05), 6, 0)
	Kit.disc(c, Vector2i(10, c.h - 6), 2, Color(0.85, 0.85, 0.8))
	Kit.fill_rect(c, Rect2i(c.w - 12, c.h - 7, 7, 3), Color(0.06, 0.06, 0.08))
	for x in [4, c.w - 6]:
		Kit.disc(c, Vector2i(x, 5), 1, Color(0.2, 0.2, 0.22))
