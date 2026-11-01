extends RefCounted
## Top-down pixel-art AWNING painter (Objects domain, private): what hangs over a tower's front
## door, drawn only as the piece's overhang (`part: "overhang"`; the piece's own footprint is bare).
## `kind` in the options.
##   `awning`: striped cloth under a board along the wall, its front edge scalloped, lined with neon
##   (glowing) and stained with grime;
##   `hanging`: a vertical sign on a bracket, two characters in neon inside a frame (glowing).
## Canonical frame: the wall at the top edge (y = 0), the street toward +y. Colours:
## ObjectArtAwningConfig; the painter takes them as given (`ObjectArt.AS_GIVEN`).

const Decay = preload("res://scenes/objects/art/decay.gd")
const Glyphs = preload("res://scenes/objects/art/glyphs.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")


## Paint the `opts.kind` onto `c`, or nothing for the piece itself (only its overhang is drawn).
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	if opts.get("part", "") != "overhang":
		return
	if String(opts.get("kind", "awning")) == "hanging":
		_hanging(c)
	else:
		_awning(c, opts)


## The striped awning cloth under its board, scalloped and lined with neon, grimy.
static func _awning(c: PixelCanvas, opts: Dictionary) -> void:
	var stripes: Array[Color] = ObjectArtAwningConfig.awning_stripes
	var stripe_px: int = opts.get("stripe_px", ObjectArtAwningConfig.awning_stripe_px)
	var scallop: int = opts.get("scallop_px", ObjectArtAwningConfig.awning_scallop_px)
	var drop: int = ObjectArtAwningConfig.awning_scallop_drop
	for x in c.w:
		var d := ((x % scallop) + 0.5 - scallop * 0.5) / (scallop * 0.5)
		var bottom := c.h - drop + int(round(drop * sqrt(maxf(0.0, 1.0 - d * d))))
		var col := stripes[int(x / float(stripe_px)) % 2]
		for y in range(0, bottom):
			c.px(x, y, col.darkened(0.12 * float(y) / c.h), 4)
		if x % stripe_px == 0:
			for y in range(0, bottom):
				c.px(x, y, stripes[0].darkened(0.5))
	Kit.fill_rect(c, Rect2i(0, 0, c.w, 3), ObjectArtAwningConfig.awning_board_color, 6)
	Kit.fill_rect(c, Rect2i(0, 3, c.w, 1), Color(0.3, 0.3, 0.34))
	var edge: Color = ObjectArtAwningConfig.awning_edge_color
	c.glowing(func() -> void:
		for x in c.w:
			var d := ((x % scallop) + 0.5 - scallop * 0.5) / (scallop * 0.5)
			c.px(x, c.h - drop - 1 + int(round(drop * sqrt(maxf(0.0, 1.0 - d * d)))), edge)
	)
	c.surface(PixelShape.rounded(Rect2i(0, 0, c.w, c.h - drop), 0), "fabric", stripes[0])
	Decay.grime(c)
	for _i in 3:
		var p := Vector2i(c.rng.randi_range(4, c.w - 5), c.rng.randi_range(6, maxi(7, c.h - 12)))
		Kit.disc(c, p, 2, Color(0.12, 0.08, 0.05, 0.9))


## The hanging sign: a board on a bracket with two glowing characters in a frame.
static func _hanging(c: PixelCanvas) -> void:
	var ink: Array[Color] = ObjectArtAwningConfig.hanging_ink_colors
	var characters: Array[String] = ObjectArtAwningConfig.hanging_characters
	Kit.fill_rect(c, Rect2i(int(c.w / 2.0) - 1, 0, 2, 5), Color(0.3, 0.3, 0.33), 6)
	var body := Rect2i(1, 5, c.w - 2, c.h - 6)
	Tech.box(c, body, ObjectArtAwningConfig.hanging_board_color, 10, 2)
	c.glowing(func() -> void:
		Kit.frame(c, body.grow(-2), ObjectArtAwningConfig.hanging_frame_color)
		for i in characters.size():
			Glyphs.draw_hanzi(c, characters[i], Vector2i(5, 10 + i * 30), 18, Kit.ink(ink[i], 2))
	)
	Decay.rust(c, 2)
