extends RefCounted

## Top-down pixel-art painter for a grenade in the TAPED SCRAP weapon style (Items domain, private; rendered through the Art
## domain's PixelArt), the fuze toward +y: an old rusty olive frag egg with its fragmentation grid, or a tin can for a stun, each
## with a strip of grey duct tape round its middle. Options: `kind` (&"frag" / &"stun"), `look` (the `GrenadeConfig` look's
## handle, `PixelArt.handle`) and `spoon` (the lever still held down: in the hand; thrown, it is gone).

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")


## Paint the grenade onto `c`, the fuze toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	WeaponArt.paint_grenade(c, opts, _body)


## The shell, its marks and the fuze or cap: the frag's grid, the rust and the tape round the middle.
static func _body(c: PixelCanvas, look: Dictionary, frag: bool, cap_len: int, top: int) -> void:
	var cx := int(c.w / 2.0)
	var mid := int(top * 0.45)
	var t := WeaponArt.shell(c, look, cap_len, frag)
	if frag:
		for y in range(2, top, 2):
			c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.shadow)
	WeaponArt.specks(c, Rect2i(1, 1, c.w - 2, maxi(top - 2, 1)), look["rust"], 4)
	for y in range(mid, mid + 2):
		for x in c.w:
			WeaponArt.over(c, x, y, look["tape"], WeaponArt.BODY_HEIGHT)
	WeaponArt.over(c, 1, 1, t.highlight, WeaponArt.BODY_HEIGHT)
	if frag:
		WeaponArt.cap(c, look, Rect2i(cx - 1, top - 1, 3, cap_len + 1))
	else:
		WeaponArt.cap(c, look, Rect2i(1, top, c.w - 2, cap_len))
