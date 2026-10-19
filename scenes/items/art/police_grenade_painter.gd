extends RefCounted
## Top-down pixel-art painter for a grenade in the POLICE ISSUE weapon style (Items domain, private;
## rendered through the Art domain's PixelArt), the fuze toward +y: a gunmetal frag egg scored with
## its fragmentation grid and a red and blue light pair by the steel fuze, or a gunmetal stun
## cylinder with its ring of vents and the light pair on its black cap; both with a white serial.
## Options: `kind` (&"frag" / &"stun"), `look` (the `GrenadeConfig` look's handle,
## `PixelArt.handle`) and `spoon` (the lever still held down: in the hand; thrown, it is gone).

const WeaponArt = preload("res://scenes/items/art/weapon_art.gd")


## Paint the grenade onto `c`, the fuze toward +y.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	WeaponArt.paint_grenade(c, opts, _body)


## The shell, its marks and the fuze or cap: the frag's grid and lights by the fuze, the stun's
## vents and the lights on its cap, the serial.
static func _body(c: PixelCanvas, look: Dictionary, frag: bool, cap_len: int, top: int) -> void:
	var cx := int(c.w / 2.0)
	var t := WeaponArt.shell(c, look, cap_len, frag)
	if frag:
		for y in range(2, top, 2):
			c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.shadow)
		WeaponArt.over(c, 1, top - 1, look["light"], WeaponArt.BODY_HEIGHT + 1)
		WeaponArt.over(c, c.w - 2, top - 1, look["light2"], WeaponArt.BODY_HEIGHT + 1)
	else:
		for x in range(1, c.w - 1, 2):
			WeaponArt.over(c, x, int(top * 0.45), t.outline, WeaponArt.BODY_HEIGHT)
	WeaponArt.over(c, cx, 2, look["trim"], WeaponArt.BODY_HEIGHT)
	WeaponArt.over(c, cx + 1, 2, look["trim"], WeaponArt.BODY_HEIGHT)
	WeaponArt.over(c, 1, 1, t.highlight, WeaponArt.BODY_HEIGHT)
	if frag:
		WeaponArt.cap(c, look, Rect2i(cx - 1, top - 1, 3, cap_len + 1))
	else:
		WeaponArt.cap(c, look, Rect2i(1, top, c.w - 2, cap_len))
		c.px(1, c.h - 2, look["light"], WeaponArt.FUZE_HEIGHT + 1)
		c.px(c.w - 2, c.h - 2, look["light2"], WeaponArt.FUZE_HEIGHT + 1)
