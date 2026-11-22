extends RefCounted
## Top-down pixel-art CLINIC painter (Objects domain, private): the ripperdoc's steel furniture,
## `kind` in the options.
##   `tool_cart`: an instrument cart with a rimmed tray (its scalpels and clamps, a syringe and a
##     small diagnostic screen are items: `ShopItemsCatalog`, `monitor`);
##   `cyberware_shelf`: an open steel shelf, bare (its chrome arms with joints, eyes, chips with
##   pins and jars are items: `CyberwareShelf`, `ItemShopPainter`).
## Canonical frame: the front toward +y. The catalogue colour is the steel's. Run down (decay.gd):
## grime, rust, scratches. Knobs: ObjectArtClinicConfig.clinic_*.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
## Heights for cast shadows.
const _BODY_HEIGHT := 4
const _SHELF_HEIGHT := 7


## Paint the clinic piece `opts.kind` onto `c` in `base` steel, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "tool_cart")):
		"cyberware_shelf":
			_shelf(c, base)
		_:
			_cart(c, base)
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, maxi(2, int(c.w * c.h / 400.0)))
	Decay.scratches(c, 3)


## The cart: its bare tray (the instruments, the syringe and the screen are items).
static func _cart(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _BODY_HEIGHT, 2)
	var tray := Rect2i(3, 3, c.w - 6, c.h - 6)
	c.fill(PixelShape.rounded(tray, 1), ObjectArtClinicConfig.clinic_tray_color, _BODY_HEIGHT)


## The shelf: its bare dark well (its arms, eyes, chips and jars are items).
static func _shelf(c: PixelCanvas, base: Color) -> void:
	Tech.box(c, Rect2i(0, 0, c.w, c.h), base, _SHELF_HEIGHT, 1)
	var well := Rect2i(3, 3, c.w - 6, c.h - 6)
	c.fill(PixelShape.rounded(well, 0), ObjectArtTechConfig.tech_dark_color, 1)
