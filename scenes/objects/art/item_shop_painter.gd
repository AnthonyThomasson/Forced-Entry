extends RefCounted
## Top-down pixel-art painter of the small items the shops and special rooms give up
## (`item_painter.gd` hands a kind it does not know here; `docs/stacked-items.md` SI16), the old
## counter's and cart's drawing: `till` (a body with a lit screen and four keys), `jar`, `pack` (a
## flat colour each), `instruments` (four chrome blades with their dark tips) and `syringe` (a
## chrome barrel with a sticker), `bottles` and `snacks` (a run of four, a seam between). Canonical
## frame: the front toward +y. A till, a jar and a pack are painted in their own colour (the row's,
## `plain`), not in the catalogue's run-down grade.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const KINDS := [
	"till", "screen", "jar", "pack", "instruments", "syringe", "bottles", "snacks", "cyber_arm",
	"cyber_eye", "cyber_chip", "cyber_jar",
]


## Paint `kind` onto `c` in `base`; false when it is none of these. `opts.spines` (a run's) are
## its packs' own colours, `[[x from the run's left, width, height, colour]]`.
static func paint(c: PixelCanvas, base: Color, kind: String, opts := {}) -> bool:
	var whole := Rect2i(0, 0, c.w, c.h)
	match kind:
		"till":
			Kit.fill_rect(c, whole, base, 12)
			var screen := Rect2i(3, 2, c.w - 6, 5)
			c.glowing(func() -> void:
				Kit.fill_rect(c, screen, ObjectArtShopConfig.shop_glass_color)
			)
			for k in 4:
				Kit.fill_rect(c, Rect2i(4 + k * 5, 10, 3, 3), Color(0.78, 0.78, 0.74))
		"screen":  # A cart's diagnostic screen: a dark body with its lit pane (the neon or green).
			Kit.fill_rect(c, whole, base, 3)
			Decay.screen(c, whole.grow(-1), Decay.screen_color(opts))
		"bottles", "snacks":
			_run(c, base, opts.get("spines", []))
		"jar":
			Kit.fill_rect(c, whole, base, 9)
		"pack":
			Kit.fill_rect(c, whole, base, 9)
		"cyber_arm", "cyber_eye", "cyber_chip", "cyber_jar":
			_cyberware(c, base, kind)
		"instruments":
			var steel := ObjectArtClinicConfig.clinic_chrome_color
			for i in 4:
				var x := i * 4
				c.line(Vector2i(x, 0), Vector2i(x, mini(c.h - 1, 6)), steel, 5)
				c.px(x, 0, ObjectArtTechConfig.tech_dark_color, 5)
		"syringe":
			var y := c.h >> 1
			c.line(
				Vector2i(0, y),
				Vector2i(c.w - 1, y),
				ObjectArtClinicConfig.clinic_chrome_color.lightened(0.3),
				5,
			)
			c.px(c.w >> 1, y, Decay.STICKERS[0], 5)
		_:
			return false
	return true


## A run side by side: each of `spines` its own colour with a dark seam between (`base` and four
## equal ones without spines).
static func _run(c: PixelCanvas, base: Color, spines: Array) -> void:
	if spines.is_empty():
		Kit.fill_rect(c, Rect2i(0, 0, c.w, c.h), base, 9)
		for k in range(1, 4):
			Kit.fill_rect(c, Rect2i(int(k * 5.6) - 1, 0, 1, c.h), base.darkened(0.5), 9)
		return
	for spine: Array in spines:
		var colour: Color = spine[3]
		Kit.fill_rect(c, Rect2i(roundi(spine[0]), 0, roundi(spine[1]), c.h), colour, 9)
		Kit.fill_rect(c, Rect2i(roundi(spine[0]) - 1, 0, 1, c.h), colour.darkened(0.5), 9)


## The old shelf's cyberware: an arm (two chrome lines and the red joint), an eye (a pale disc with
## its dark pupil), a chip (its body, a pin at every second pixel along both long edges) or a jar
## (a disc with a chrome ring) in `base`.
static func _cyberware(c: PixelCanvas, base: Color, kind: String) -> void:
	var joint := ObjectArtClinicConfig.clinic_joint_color
	var middle := Vector2i(c.w >> 1, c.h >> 1)
	match kind:
		"cyber_arm":
			c.line(Vector2i(0, 0), Vector2i(0, c.h - 1), base, 5)
			c.line(Vector2i(1, 0), Vector2i(1, c.h - 1), base.darkened(0.25), 5)
			c.fill(PixelShape.disc(Vector2i(0, middle.y), 1), joint, 5)
		"cyber_eye":
			c.fill(PixelShape.disc(middle, 3), base, 5)
			c.fill(PixelShape.disc(middle, 1), joint, 5)
		"cyber_chip":
			Kit.fill_rect(c, Rect2i(0, 1, c.w, c.h - 2), base, 5)
			for k in range(0, c.w, 2):
				c.px(k, 0, ObjectArtClinicConfig.clinic_pin_color, 5)
				c.px(k, c.h - 1, ObjectArtClinicConfig.clinic_pin_color, 5)
		_:
			c.fill(PixelShape.disc(middle, 3), base, 5)
			c.outline(PixelShape.disc(middle, 3), ObjectArtClinicConfig.clinic_chrome_color)
