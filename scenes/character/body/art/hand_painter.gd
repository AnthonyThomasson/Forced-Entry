extends RefCounted
## Top-down pixel-art HAND painter (Character domain, private; rendered through the Art domain's
## PixelArt): a fist seen from above in the canonical frame — knuckles toward the front (+y), the
## thumb tucked along the inner side — in `base` (the glove, the bare skin or a chrome hand's
## metal). The look (`opts.look`, a `PixelArt.handle`) adds the Zenitex's hard knuckle guard, a
## merc's fingerless glove; a chrome hand (`opts.chrome`) gets its metal finish and knuckle hinge.
## Options: `look`, `side` (-1 = left hand, thumb toward +x; 1 = right hand, thumb toward -x),
## `chrome`.

## Heights for cast shadows: the thumb sits over the fist.
const _FIST := 3
const _THUMB := 5


## Paint a fist onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var look := PixelArt.look_of(opts)
	var chrome: bool = opts.get("chrome", false)
	var t := ArtSurfaceConfig.tones(base)
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var r := maxi(2, int(mini(c.w, c.h) / 2.0) - 1)
	var fist := PixelShape.disc(o, r)
	c.fill(fist, base, _FIST)
	if chrome:
		c.surface(fist, "metal", base)
	c.bevel(fist, 1, 2, t.light, t.dark)
	# Knuckles: a row of bumps along the front with creases between them.
	var ky := o.y + r - 2
	for x in range(o.x - r + 2, o.x + r - 1, 2):
		c.px(x, ky, t.highlight)
		c.px(x + 1, ky + 1, t.dark)
	var skin: Color = look.get("skin", base)
	if chrome:
		# The knuckle hinge.
		c.line(Vector2i(o.x - r + 1, o.y), Vector2i(o.x + r - 1, o.y), t.shadow, _FIST)
	elif String(look.get("style", "")) == "zenitex":
		# A hard knuckle guard.
		c.line(
			Vector2i(o.x - r + 2, ky),
			Vector2i(o.x + r - 2, ky),
			t.light.lightened(0.15),
			_THUMB,
		)
	elif String(look.get("style", "")) == "merc" and base != skin:
		# Fingerless: the fingers' skin past the glove.
		for x in range(o.x - r + 2, o.x + r - 1, 2):
			c.px(x, ky + 1, skin)
	c.outline(fist, t.outline)
	var side := int(opts.get("side", 1))
	var thumb := PixelShape.disc(o + Vector2i(-side * (r - 2), 0), maxi(1, int(r / 2.0) - 1))
	c.fill(thumb, base.lightened(0.04), _THUMB)
	c.outline(thumb, t.dark)
	c.cast_shadows()
