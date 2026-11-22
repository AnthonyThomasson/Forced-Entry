extends RefCounted
## The old look of the shops' and special rooms' small things: what the shop, noodle, clinic and
## tech painters drew onto the piece (commit 08f43a10, before #194 unbake-c made each an item), as
## an oracle for tests that put the old drawing and the new item side by side
## (`art/shop_items_lit_windowed`). `draw` paints one thing on a canvas of its footprint, as the old
## painter did, the thing's colour given (the row that carries it sets the new item's the same).
## Nothing in scenes/ reads this.

const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")
const Decay = preload("res://scenes/objects/art/decay.gd")
## Each kind's footprint (px) as the old painter drew it: the area one thing took.
const FEET := {
	"till": Vector2i(26, 17), "jar": Vector2i(12, 10), "pack": Vector2i(5, 5),
	"pot": Vector2i(16, 16), "bowl": Vector2i(12, 12), "instruments": Vector2i(13, 8),
	"syringe": Vector2i(11, 2), "screen": Vector2i(9, 6),
	"cyber_arm": Vector2i(3, 24), "cyber_eye": Vector2i(6, 6), "cyber_chip": Vector2i(6, 7),
	"cyber_jar": Vector2i(6, 6),
}


## Paint `kind` onto `c` (a canvas of `FEET[kind]`) in `colour`, the old way.
static func draw(c: PixelCanvas, kind: String, colour: Color) -> void:
	var whole := Rect2i(0, 0, c.w, c.h)
	var middle := Vector2i(c.w >> 1, c.h >> 1)
	var steel := ObjectArtClinicConfig.clinic_chrome_color
	match kind:
		"till":
			Tech.box(c, whole, colour, 12, 1)
			var screen := ObjectArtShopConfig.shop_glass_color
			c.glowing(func() -> void: Kit.fill_rect(c, Rect2i(3, 2, 20, 5), screen))
			for k in 4:
				Kit.fill_rect(c, Rect2i(4 + k * 5, 10, 3, 3), Color(0.78, 0.78, 0.74))
		"jar":
			Tech.box(c, whole, colour, 9, 0)
		"pack":
			Kit.fill_rect(c, whole, colour, 9)
		"pot":  # The pot's rim, its steel and its broth.
			Kit.disc(c, middle, 8, colour.darkened(0.4), 12)
			Kit.disc(c, middle, 6, colour, 13)
			Kit.disc(c, middle, 4, ObjectArtShopConfig.noodle_broth_color.darkened(0.2), 13)
		"bowl":
			Kit.disc(c, middle, 5, colour, 9)
			Kit.disc(c, middle, 3, ObjectArtShopConfig.noodle_broth_color, 9)
		"instruments":
			for i in 4:
				c.line(Vector2i(i * 4, 0), Vector2i(i * 4, 6), steel, 5)
				c.px(i * 4, 0, ObjectArtTechConfig.tech_dark_color, 5)
		"screen":  # The cart's diagnostic screen, in the cheap screens' green.
			Decay.screen(c, whole, Decay.screen_color({}))
		"syringe":
			c.line(Vector2i(0, 1), Vector2i(c.w - 1, 1), steel.lightened(0.3), 5)
			c.px(c.w >> 1, 1, Decay.STICKERS[0], 5)
		_:
			_cyberware(c, kind, colour, steel)


## The old shelf's arm, eye, chip and jar.
static func _cyberware(c: PixelCanvas, kind: String, colour: Color, steel: Color) -> void:
	var joint := ObjectArtClinicConfig.clinic_joint_color
	var middle := Vector2i(c.w >> 1, c.h >> 1)
	match kind:
		"cyber_arm":
			c.line(Vector2i(0, 0), Vector2i(0, c.h - 1), colour, 5)
			c.line(Vector2i(1, 0), Vector2i(1, c.h - 1), colour.darkened(0.25), 5)
			c.fill(PixelShape.disc(Vector2i(0, middle.y), 1), joint, 5)
		"cyber_eye":
			c.fill(PixelShape.disc(middle, 3), colour, 5)
			c.fill(PixelShape.disc(middle, 1), joint, 5)
		"cyber_chip":
			c.fill(PixelShape.rounded(Rect2i(0, 1, c.w, c.h - 2), 0), colour, 5)
			for k in range(0, c.w, 2):
				c.px(k, 0, ObjectArtClinicConfig.clinic_pin_color, 5)
				c.px(k, c.h - 1, ObjectArtClinicConfig.clinic_pin_color, 5)
		_:
			c.fill(PixelShape.disc(middle, 3), colour, 5)
			c.outline(PixelShape.disc(middle, 3), steel)
