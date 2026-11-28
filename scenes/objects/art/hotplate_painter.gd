extends RefCounted
## Top-down pixel-art HOTPLATE painter (Objects domain, private): the crate the kitchenette's
## hotplate stands on. Canonical frame: the front toward +y. The plate, its hot ring and the pan are
## loose items on it (decision D21: `item_stock_painter.gd`). Run down (decay.gd): grease, grime and
## rust. The piece still gives the ring's light (ObjectArtKitchenBathConfig.hotplate_ring_color).

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
## Heights for cast shadows.
const _CRATE_HEIGHT := 3


## Paint the hotplate's crate onto `c`, front toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, _opts: Dictionary) -> void:
	var crate := ObjectArtKitchenBathConfig.hotplate_crate_color
	Tech.box(c, Rect2i(0, 0, c.w, c.h), crate, _CRATE_HEIGHT, 1)
	for x in range(0, c.w, 6):  # The crate's slats.
		c.line(Vector2i(x, 1), Vector2i(x, c.h - 2), crate.darkened(0.3), _CRATE_HEIGHT)
	c.cast_shadows()
	Decay.stain(c, Decay.GREASE, 3)
	Decay.grime(c)
	Decay.rust(c, 3)
