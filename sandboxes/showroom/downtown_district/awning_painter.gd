extends RefCounted
## What hangs over a storefront's sidewalk, each drawn in the canonical frame with the wall at its
## top edge (y = 0) and the street toward +y. Options: `kind` `awning` (striped fabric, a scalloped
## front edge; `palette` `a` red and cream, `c` teal and black with a neon edge), `sign_box` (a
## projecting neon box sign standing out from the wall, BAR in vertical letters) or `hanging` (a
## vertical glyph sign, two characters in neon).

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const STRIPE := 8
const SCALLOP := 12
const PALETTES := {
	"a": [Color(0.7, 0.2, 0.16), Color(0.86, 0.8, 0.62)],
	"c": [Color(0.1, 0.34, 0.36), Color(0.07, 0.07, 0.1)],
}
const BOARD := Color(0.09, 0.09, 0.12)


## Paint the `opts.kind` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "awning")):
		"sign_box":
			_sign_box(c)
		"hanging":
			_hanging(c)
		_:
			_awning(c, String(opts.get("palette", "a")))


static func _awning(c: PixelCanvas, palette: String) -> void:
	var cols: Array = PALETTES[palette]
	for x in c.w:
		var d := ((x % SCALLOP) + 0.5 - SCALLOP * 0.5) / (SCALLOP * 0.5)
		var bottom := c.h - 6 + int(round(6.0 * sqrt(maxf(0.0, 1.0 - d * d))))
		var col: Color = cols[int(x / float(STRIPE)) % 2]
		for y in range(0, bottom):
			c.px(x, y, col.darkened(0.12 * float(y) / c.h), 4)
		if x % STRIPE == 0:
			for y in range(0, bottom):
				c.px(x, y, (cols[0] as Color).darkened(0.5))
	Kit.fill_rect(c, Rect2i(0, 0, c.w, 3), BOARD, 6)
	Kit.fill_rect(c, Rect2i(0, 3, c.w, 1), Color(0.3, 0.3, 0.34))
	if palette == "c":
		c.glowing(func() -> void:
			for x in c.w:
				var d := ((x % SCALLOP) + 0.5 - SCALLOP * 0.5) / (SCALLOP * 0.5)
				var y := c.h - 7 + int(round(6.0 * sqrt(maxf(0.0, 1.0 - d * d))))
				c.px(x, y, Kit.NEON_CYAN)
		)
	c.surface(PixelShape.rounded(Rect2i(0, 0, c.w, c.h - 6), 0), "fabric", cols[0])
	Kit.grime(c, 6, 7, 0.28)
	for _i in 3:
		var p := Vector2i(c.rng.randi_range(4, c.w - 5), c.rng.randi_range(6, c.h - 12))
		Kit.disc(c, p, 2, Color(0.12, 0.08, 0.05, 0.9))


static func _sign_box(c: PixelCanvas) -> void:
	Kit.fill_rect(c, Rect2i(int(c.w / 2.0) - 3, 0, 6, 6), Color(0.25, 0.25, 0.28), 6)
	var body := Rect2i(4, 6, c.w - 8, c.h - 8)
	Kit.block(c, body, BOARD, 10, 2)
	c.glowing(func() -> void:
		Kit.frame(c, body.grow(-2), Kit.NEON_MAGENTA)
		Kit.frame(c, body.grow(-3), Kit.NEON_MAGENTA.darkened(0.25))
		Glyphs.draw_stacked(
			c,
			"BAR",
			int(c.w / 2.0),
			body.position.y + 6,
			Kit.ink(Kit.NEON_CYAN, 2),
		)
	)
	Kit.rust(c, 3)


static func _hanging(c: PixelCanvas) -> void:
	Kit.fill_rect(c, Rect2i(int(c.w / 2.0) - 1, 0, 2, 5), Color(0.3, 0.3, 0.33), 6)
	var body := Rect2i(1, 5, c.w - 2, c.h - 6)
	Kit.block(c, body, BOARD, 10, 2)
	c.glowing(func() -> void:
		Kit.frame(c, body.grow(-2), Kit.NEON_AMBER)
		Glyphs.draw_hanzi(c, "王", Vector2i(5, 10), 18, Kit.ink(Kit.NEON_CYAN, 2))
		Glyphs.draw_hanzi(c, "大", Vector2i(5, 40), 18, Kit.ink(Kit.NEON_MAGENTA, 2))
	)
	Kit.rust(c, 2)
