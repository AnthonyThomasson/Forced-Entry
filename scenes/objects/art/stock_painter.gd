extends RefCounted
## Top-down pixel-art STOCKROOM painter (Objects domain, private): the tower stockroom's wall safe
## in grimy steel, its top and the door's edge toward +y. The crates and the pallet with its wrapped
## boxes are loose items now (decision D21: `item_stock_painter.gd`, `PieceCarries`).
## Canonical frame: the front toward +y; the catalogue colour is the steel. Run down (decay.gd):
## grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")


## Paint the wall safe onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	_safe(c, base)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(1, int(c.w * c.h / 300.0)))


## A safe: a steel body, a lighter top, the door's edge with its dial and handle.
static func _safe(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, 10, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 11), base.lightened(0.1), 10)
	Tech.box(c, Rect2i(3, c.h - 8, c.w - 6, 5), base.lightened(0.05), 6, 0)
	Kit.disc(c, Vector2i(10, c.h - 6), 2, Color(0.85, 0.85, 0.8))
	Kit.fill_rect(c, Rect2i(c.w - 12, c.h - 7, 7, 3), Color(0.06, 0.06, 0.08))
	for x in [4, c.w - 6]:
		Kit.disc(c, Vector2i(x, 5), 1, Color(0.2, 0.2, 0.22))
