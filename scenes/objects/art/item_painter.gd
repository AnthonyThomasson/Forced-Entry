extends RefCounted
## Top-down pixel-art painter of the small items (Objects domain, private; `docs/stacked-items.md`):
## `kind` in the options.
##   `plate`: a round plate with a rim ring;
##   `cup`: a round cup, its handle a nub on the right;
##   `bowl`: a round bowl, a dark well inside its rim;
##   `book`: a cover with a spine along the left and the page edge on the right;
##   `desk_lamp`: a round shade with a bright bulb at its middle;
##   `monitor`: a screen seen from above, its dark back with the lit front edge (glowing, in the
##     screen's green or the piece's neon) and a stand's foot, in the old prop's palette;
##   `box`: a cardboard box with tape across its lid;
##   `crate`: a wooden crate with a slat each way.
## Canonical frame: the front toward +y; the catalogue colour is the item's own.

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const ItemStockPainter = preload("res://scenes/objects/art/item_stock_painter.gd")
const ItemHomePainter = preload("res://scenes/objects/art/item_home_painter.gd")
const Decay = preload("res://scenes/objects/art/decay.gd")


## Paint the item `opts.kind` onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "box")):
		"plate":
			_plate(c, base)
		"cup":
			_cup(c, base)
		"bowl":
			_bowl(c, base)
		"book":
			_book(c, base)
		"desk_lamp":
			_desk_lamp(c, base)
		"monitor":
			_monitor(c, opts)
		"crate":
			_crate(c, base)
		var other:
			if other in ItemStockPainter.KINDS:
				ItemStockPainter.paint(c, base, other)
			elif not ItemHomePainter.paint(c, base, other):
				_box(c, base)
	c.cast_shadows()


## The middle of the canvas.
static func _middle(c: PixelCanvas) -> Vector2i:
	return Vector2i(c.w >> 1, c.h >> 1)


## The radius of the disc that fills the canvas.
static func _round(c: PixelCanvas) -> int:
	return maxi(1, mini(c.w, c.h) >> 1)


## A plate: a rim ring and a lighter well.
static func _plate(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	Kit.disc(c, at, _round(c), base.darkened(0.12), 2)
	Kit.disc(c, at, maxi(1, _round(c) - 1), base, 2)
	Kit.disc(c, at, maxi(1, _round(c) - 3), base.lightened(0.08), 2)


## A cup: the body, a dark well and a nub for the handle.
static func _cup(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c) - Vector2i(1, 0)
	var radius := maxi(1, _round(c) - 1)
	Kit.disc(c, Vector2i(at.x + radius, at.y), 1, base.darkened(0.25), 5)
	Kit.disc(c, at, radius, base, 5)
	Kit.disc(c, at, maxi(1, radius - 1), base.darkened(0.55), 5)


## A bowl: the rim and a dark well.
static func _bowl(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	Kit.disc(c, at, _round(c), base.darkened(0.15), 4)
	Kit.disc(c, at, maxi(1, _round(c) - 1), base, 4)
	Kit.disc(c, at, maxi(1, _round(c) - 3), base.darkened(0.4), 4)


## A book: the cover, a darker spine, the page edge and a title strip.
static func _book(c: PixelCanvas, base: Color) -> void:
	var whole := Rect2i(0, 0, c.w, c.h)
	Kit.fill_rect(c, whole, base, 2)
	Kit.fill_rect(c, Rect2i(0, 0, 2, c.h), base.darkened(0.3), 2)
	Kit.fill_rect(c, Rect2i(c.w - 1, 1, 1, c.h - 2), Color(0.92, 0.9, 0.82), 2)
	Kit.fill_rect(c, Rect2i(3, 2, maxi(1, c.w - 6), 2), base.lightened(0.3), 2)


## A desk lamp: the shade, its dark inside and the bulb.
static func _desk_lamp(c: PixelCanvas, base: Color) -> void:
	var at := _middle(c)
	Kit.disc(c, at, _round(c), base, 14)
	Kit.disc(c, at, maxi(1, _round(c) - 2), base.darkened(0.35), 14)
	Kit.disc(c, at, 1, Color(1.0, 0.95, 0.7), 14)


## A monitor from above, as the old prop was drawn (`props.gd`): the screen's dark back, its lit
## front edge (glowing, the screen's green or `opts`'s neon), a neck and the stand's foot. Its
## colours are the prop palette's, not the catalogue colour's run-down grade.
static func _monitor(c: PixelCanvas, opts: Dictionary) -> void:
	var case: Color = ObjectArtDecorConfig.prop_colors["plastic_dark"]
	var metal: Color = ObjectArtDecorConfig.prop_colors["metal"]
	var foot := Rect2i(c.w >> 1 - 5, 3, 10, c.h - 3)
	Kit.fill_rect(c, foot.grow_individual(0, -1, 0, 0), metal.darkened(0.25), 8)
	Kit.fill_rect(c, Rect2i(c.w >> 1 - 1, 2, 3, 3), metal.darkened(0.4), 14)
	Kit.fill_rect(c, Rect2i(0, 0, c.w, 3), case, 14)
	Kit.fill_rect(c, Rect2i(0, 0, c.w, 1), case.lightened(0.18), 14)
	var lit := Decay.screen_color(opts)
	var bar := func() -> void: Kit.fill_rect(c, Rect2i(1, 2, c.w - 2, 1), lit, 14)
	c.glowing(bar, Rect2i(0, 2, c.w, 1))


## A cardboard box with a tape strip down its lid.
static func _box(c: PixelCanvas, base: Color) -> void:
	Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base.darkened(0.12), 12)
	Kit.fill_rect(c, Rect2i(1, 1, c.w - 2, c.h - 2), base, 12)
	Kit.fill_rect(c, Rect2i((c.w >> 1) - 1, 0, 2, c.h), base.lightened(0.28), 12)


## A wooden crate with slats and a brace.
static func _crate(c: PixelCanvas, base: Color) -> void:
	Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base.darkened(0.3), 16)
	Kit.fill_rect(c, Rect2i(1, 1, c.w - 2, c.h - 2), base, 16)
	for k in range(4, c.h - 2, 5):
		Kit.fill_rect(c, Rect2i(1, k, c.w - 2, 1), base.darkened(0.3), 16)
	Kit.fill_rect(c, Rect2i((c.w >> 1) - 1, 1, 2, c.h - 2), base.lightened(0.12), 16)
