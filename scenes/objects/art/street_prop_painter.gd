extends RefCounted
## Top-down pixel-art STREET PROP painter (Objects domain, private): a district's sidewalk clutter
## in grimy steel, `kind` in the options.
##   `vending`: a drinks machine, its lit window toward the street (+y);
##   `bench`: a steel frame with wooden slats;
##   `bin`: a round bin with a lid and a dark mouth;
##   `grate`: a drain grate over a dark pit;
##   `litter`: flat scraps lying about.
## Canonical frame: the front (the street side) toward +y; the catalogue colour is the steel. Knobs:
## ObjectArtStreetPropConfig.prop_*, each overridable by `opts` (keyed without the prefix). Run down
## (decay.gd): grime and rust.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
## Heights for cast shadows.
const _MACHINE_HEIGHT := 14
const _BENCH_HEIGHT := 6
const _BIN_HEIGHT := 10


## Paint the street prop `opts.kind` onto `c` in `base` steel.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var top: Color = opts.get("top_color", ObjectArtStreetPropConfig.prop_top_color)
	match String(opts.get("kind", "vending")):
		"bench":
			_bench(c, base, opts)
		"bin":
			_bin(c, base, top, opts)
		"grate":
			_grate(c, base, top, opts)
		"litter":
			_litter(c, base, top, opts)
			return
		_:
			_vending(c, base, top, opts)
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 300.0)))


## The machine: a steel body, a lighter face with grooves, a lit window of drinks along the front.
static func _vending(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var products: Array = opts.get("products", ObjectArtStreetPropConfig.prop_products)
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _MACHINE_HEIGHT, 2)
	Kit.fill_rect(c, Rect2i(3, 3, c.w - 6, c.h - 15), top)
	for k in range(5, c.w - 5, 5):
		Kit.fill_rect(c, Rect2i(k, 5, 1, c.h - 19), base.darkened(0.2))
	var window := Rect2i(3, c.h - 10, c.w - 6, 7)
	Kit.fill_rect(c, window.grow(1), base.darkened(0.5))
	var glass: Color = opts.get("glass_color", ObjectArtStreetPropConfig.prop_glass_color)
	c.glowing(func() -> void:
		Kit.fill_rect(c, window, glass)
		for k in range(0, window.size.x - 2, 4):
			var drink := Rect2i(window.position.x + 1 + k, window.position.y + 2, 3, 4)
			Kit.fill_rect(c, drink, products[int(k / 4.0) % products.size()])
	)
	c.cast_shadows()


## The bench: two steel end frames and wooden slats between.
static func _bench(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	var wood: Color = opts.get("wood_color", ObjectArtStreetPropConfig.prop_wood_color)
	var slats: int = opts.get("slats", ObjectArtStreetPropConfig.prop_slats)
	for x in [3, c.w - 7]:
		Tech.box(c, Rect2i(x, 0, 4, c.h), base, _BENCH_HEIGHT, 0)
	var step := int((c.h - 2) / float(slats))
	for k in slats:
		var r := Rect2i(8, 1 + k * step, c.w - 16, step - 1)
		Tech.box(c, r, wood.lightened(0.04 * (k % 2)), 4, 0)
		c.surface(PixelShape.rounded(r, 0), "wood", wood)
	c.cast_shadows()


## The bin: a dark body, a lid with a mouth, a trim ring.
static func _bin(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var middle := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(minf(c.w, c.h) / 2.0) - 1
	Kit.disc(c, middle, radius, base.darkened(0.3), _BIN_HEIGHT)
	Kit.disc(c, middle, radius - 2, top, _BIN_HEIGHT + 2)
	Kit.disc(c, middle + Vector2i(1, 1), radius - 6, Color(0.05, 0.05, 0.06), _BIN_HEIGHT + 2)
	c.outline(PixelShape.disc(middle, radius), base.darkened(0.6))
	c.bevel(PixelShape.disc(middle, radius - 2), 1, 1, top.lightened(0.3), base.darkened(0.3))
	var accent: Color = opts.get("accent_color", ObjectArtStreetPropConfig.prop_accent_color)
	c.outline(PixelShape.disc(middle, radius - 3), accent.darkened(0.2))
	c.cast_shadows()


## The grate: bars over a dark pit.
static func _grate(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var all := Rect2i(0, 0, c.w, c.h)
	Kit.fill_rect(c, all, base.darkened(0.15))
	var inner := all.grow(-3)
	Kit.fill_rect(c, inner, Color(0.03, 0.03, 0.04))
	var step: int = opts.get("grate_step", ObjectArtStreetPropConfig.prop_grate_step)
	for x in range(inner.position.x + 1, inner.end.x - 1, step):
		Kit.fill_rect(c, Rect2i(x, inner.position.y, 2, inner.size.y), top)


## Scraps of paper, cans and cloth.
static func _litter(c: PixelCanvas, base: Color, top: Color, opts: Dictionary) -> void:
	var accent: Color = opts.get("accent_color", ObjectArtStreetPropConfig.prop_accent_color)
	var wood: Color = opts.get("wood_color", ObjectArtStreetPropConfig.prop_wood_color)
	var products: Array = opts.get("products", ObjectArtStreetPropConfig.prop_products)
	var drink: Color = products[c.rng.randi() % products.size()]
	var tones: Array[Color] = [accent, top, wood, drink]
	for _i in int(opts.get("scraps", ObjectArtStreetPropConfig.prop_scraps)):
		var p := Vector2i(c.rng.randi_range(2, c.w - 6), c.rng.randi_range(2, c.h - 6))
		var tone := tones[c.rng.randi() % tones.size()]
		var size := Vector2i(c.rng.randi_range(2, 5), c.rng.randi_range(2, 4))
		if c.rng.randf() < 0.3:
			Kit.disc(c, p + Vector2i(2, 2), 2, tone)
		else:
			Kit.fill_rect(c, Rect2i(p, size), tone)
		c.px(p.x + size.x, p.y + size.y, base.darkened(0.8))
