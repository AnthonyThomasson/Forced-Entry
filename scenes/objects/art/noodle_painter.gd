extends RefCounted
## Top-down pixel-art NOODLE-BAR painter (Objects domain, private): the bar's pieces in grimy steel,
## `kind` in the options.
##   `bar`: a long counter (its pots and bowls are items: `LooseStockCatalog`, `ItemsCatalog`), the
## diners' side toward +y;
## `stool`: a round bar stool; `booth`: two benches with a table between them (its bowls are items);
##   `menu`: a menu board lit with two lines of text and three characters (glowing).
## Canonical frame: the front toward +y; the catalogue colour is the steel. Knobs:
## ObjectArtShopConfig.noodle_*. Run down (decay.gd): grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Glyphs = preload("res://scenes/objects/art/glyphs.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
const _MENU_HANZI := ["大", "中", "王"]


## Paint the noodle-bar piece `opts.kind` onto `c` in `base` steel.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "bar")):
		"stool":
			_stool(c, base, opts)
		"booth":
			_booth(c, base, opts)
		"menu":
			_menu(c, base, opts)
		_:
			_bar(c, base, opts)
	if opts.get("kind", "bar") != "stool":
		c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(1, int(c.w * c.h / 300.0)))


## The bar: a steel top with a lip, bare.
static func _bar(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	var top: Color = opts.get("top_color", ObjectArtShopConfig.noodle_top_color)
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, 6, 2)
	var surface := Rect2i(3, 3, c.w - 6, c.h - 9)
	Tech.box(c, surface, top, 8, 1)
	c.surface(PixelShape.rounded(surface, 1), "metal", top)
	var lip: Color = opts.get("accent_color", ObjectArtShopConfig.noodle_accent_color)
	Kit.fill_rect(c, Rect2i(3, c.h - 6, c.w - 6, 2), lip)


## A round stool: a steel rim round a seat, a bolt in the middle.
static func _stool(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	var seat: Color = opts.get("wood_color", ObjectArtShopConfig.noodle_wood_color)
	var mid := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(c.w / 2.0) - 1
	var t := ArtSurfaceConfig.tones(base)
	Kit.disc(c, mid, radius, base.darkened(0.3), 5)
	Kit.disc(c, mid, radius - 2, seat, 6)
	c.outline(PixelShape.disc(mid, radius), base.darkened(0.6))
	c.bevel(PixelShape.disc(mid, radius - 2), 1, 1, t.light, t.dark)
	Kit.disc(c, mid, 2, base.darkened(0.4), 6)


## A booth: a bench along each long side and a table between.
static func _booth(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	for y in [0, c.h - 18]:
		Tech.box(c, Rect2i(0, y, c.w, 18), base, 5, 3)
		for x in range(8, c.w - 4, 16):
			Kit.fill_rect(c, Rect2i(x, y + 3, 1, 12), base.darkened(0.3))
	var table := Rect2i(8, 22, c.w - 16, c.h - 44)
	var top: Color = opts.get("top_color", ObjectArtShopConfig.noodle_top_color)
	Tech.box(c, table, top, 8, 1)
	c.surface(PixelShape.rounded(table, 1), "wood", top)


## The menu board: lit text and characters in a frame on a dark board.
static func _menu(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	var colors: Array[Color] = ObjectArtShopConfig.noodle_menu_colors
	var first: Color = opts.get("menu_color", colors[0])
	var second: Color = opts.get("menu_color_2", colors[1])
	var board := Rect2i(2, 0, c.w - 4, c.h)
	Tech.box(c, board, base.darkened(0.35), 14, 1)
	c.glowing(func() -> void:
		Glyphs.draw(c, "RAMEN", Vector2i(8, 2), Kit.ink(first))
		Glyphs.draw(c, "UDON", Vector2i(8, 10), Kit.ink(second.darkened(0.1)))
		for i in _MENU_HANZI.size():
			Glyphs.draw_hanzi(
				c,
				_MENU_HANZI[i],
				Vector2i(c.w - 44 + i * 14, 3),
				10,
				Kit.ink(second),
			)
		Kit.fill_rect(c, Rect2i(46, 7, 12, 1), first)
		Kit.fill_rect(c, Rect2i(46, 15, 12, 1), second)
		Kit.frame(c, board.grow(-1), first.darkened(0.2))
	)
