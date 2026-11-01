extends RefCounted
## Top-down pixel-art SHOP painter (Objects domain, private): the tower shop's pieces in grimy
## steel, `kind` in the options.
##   `counter`: a steel counter with a till and a few packs, the customer side toward +y;
## `aisle`: a double-sided shelf aisle, two shelf runs back to back, a steel lip along each outer
## edge;
##   `fridge`: a glass-door drinks fridge, its glass along the front (+y) glowing;
##   `snack`: a snack machine, its window along the front lit.
## Canonical frame: the front toward +y; the catalogue colour is the steel. Knobs:
## ObjectArtShopConfig.shop_*. Run down (decay.gd): grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
## Heights for cast shadows.
const _COUNTER_HEIGHT := 6
const _FRIDGE_HEIGHT := 14


## Paint the shop piece `opts.kind` onto `c` in `base` steel, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var top: Color = opts.get("top_color", ObjectArtShopConfig.shop_top_color)
	match String(opts.get("kind", "counter")):
		"aisle":
			_aisle(c, base, top)
		"fridge":
			_fridge(c, base, top, opts)
		"snack":
			_snack(c, base, top, opts)
		_:
			_counter(c, base, top, opts)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 300.0)))


## The counter: a steel top with a lip, a till with a lit screen and keys, a jar and packs.
static func _counter(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _COUNTER_HEIGHT, 2)
	var surface := Rect2i(3, 3, c.w - 6, c.h - 11)
	Tech.box(c, surface, top, 8, 1)
	c.surface(PixelShape.rounded(surface, 1), "metal", top)
	var lip: Color = opts.get("accent_color", ObjectArtShopConfig.shop_accent_color)
	Kit.fill_rect(c, Rect2i(3, c.h - 7, c.w - 6, 2), lip)
	var till := Rect2i(8, 7, 26, 17)
	Tech.box(c, till, base.darkened(0.3), 12, 1)
	var screen: Color = opts.get("glass_color", ObjectArtShopConfig.shop_glass_color)
	var till_screen := Rect2i(till.position + Vector2i(3, 2), Vector2i(20, 5))
	c.glowing(func() -> void: Kit.fill_rect(c, till_screen, screen))
	for k in 4:
		Kit.fill_rect(c, Rect2i(till.position + Vector2i(4 + k * 5, 10), Vector2i(3, 3)),
				Color(0.78, 0.78, 0.74))
	Tech.box(c, Rect2i(42, 9, 12, 10), Color(0.8, 0.78, 0.7), 9, 0)
	for k in 5:
		Kit.fill_rect(c, Rect2i(62 + k * 7, 8 + (k % 2) * 6, 5, 5), packs[k % packs.size()], 9)


## The aisle: two shelf runs back to back.
static func _aisle(c: PixelCanvas, base: Color, top: Color) -> void:
	var depth := int(c.h / 2.0)
	_shelf_run(c, base, top, Rect2i(0, 0, c.w, depth))
	_shelf_run(c, base, top, Rect2i(0, c.h - depth, c.w, depth))


## One shelf run of the aisle: two tiers of packs and a lip along its outer edge.
static func _shelf_run(c: PixelCanvas, base: Color, top: Color, row: Rect2i) -> void:
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	Tech.box(c, row, base, 10, 1)
	for tier in 2:
		var y := row.position.y + 3 + tier * 8
		for x in range(3, c.w - 6, 6):
			var pack := packs[(int(x / 6.0) + tier + row.position.y) % packs.size()]
			Kit.fill_rect(c, Rect2i(x, y, 5, 6), pack.darkened(0.1), 12)
	var outer_y := row.position.y if row.position.y == 0 else row.end.y - 2
	Kit.fill_rect(c, Rect2i(1, outer_y, c.w - 2, 2), top, 10)


## The fridge: a steel body and top with vents, its lit glass of drinks along the front.
static func _fridge(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _FRIDGE_HEIGHT, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 15), top, _FRIDGE_HEIGHT)
	for k in range(6, c.w - 6, 4):
		Kit.fill_rect(c, Rect2i(k, 5, 2, 5), base.darkened(0.35))
	var glass := Rect2i(3, c.h - 11, c.w - 6, 8)
	Kit.fill_rect(c, glass.grow(1), base.darkened(0.55))
	var glow: Color = opts.get("fridge_glow", ObjectArtShopConfig.shop_fridge_glow)
	c.glowing(func() -> void:
		Kit.fill_rect(c, glass, glow)
		for k in range(0, glass.size.x - 3, 5):
			Kit.fill_rect(c, Rect2i(glass.position + Vector2i(1 + k, 1), Vector2i(3, 6)),
					packs[int(k / 5.0) % packs.size()])
	)


## The snack machine: a steel body, a keypad and a lit window of packs along the front.
static func _snack(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var packs: Array[Color] = ObjectArtShopConfig.shop_packs
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, 12, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 14), top, 12)
	Kit.fill_rect(c, Rect2i(c.w - 12, 5, 7, 8), Color(0.1, 0.1, 0.12), 12)
	for k in 6:
		Kit.fill_rect(c, Rect2i(c.w - 11 + (k % 2) * 3, 14 + int(k / 2.0) * 3, 2, 2),
				Color(0.8, 0.8, 0.76), 12)
	var window := Rect2i(3, c.h - 10, c.w - 6, 7)
	Kit.fill_rect(c, window.grow(1), base.darkened(0.5))
	var glass: Color = opts.get("glass_color", ObjectArtShopConfig.shop_glass_color)
	c.glowing(func() -> void:
		Kit.fill_rect(c, window, glass)
		_window_packs(c, window, packs)
	)


## The packs on the two rows of a snack machine's lit `window`.
static func _window_packs(c: PixelCanvas, window: Rect2i, packs: Array[Color]) -> void:
	for row in 2:
		for k in range(0, window.size.x - 3, 4):
			var at := window.position + Vector2i(1 + k, 1 + row * 3)
			Kit.fill_rect(c, Rect2i(at, Vector2i(3, 2)), packs[(int(k / 4.0) + row) % packs.size()])
