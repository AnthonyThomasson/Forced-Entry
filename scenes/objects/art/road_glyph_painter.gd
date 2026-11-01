extends RefCounted
## Pixel-art ROAD GLYPH painter (Objects domain, private): the lane marking on a road's approach to
## a junction, a transparent layer over the asphalt: `opts.text`, a lane number in the pixel font,
## and below it an ahead arrow pointing at the junction, faded and worn. Canonical frame: the
## junction toward +y, the number upright and the arrow pointing down. Knobs:
## ObjectArtRoadGlyphConfig.glyph_*, each overridable by `opts` (keyed without the prefix); the
## painter takes its colours as given (`ObjectArt.AS_GIVEN`).

const Glyphs = preload("res://scenes/objects/art/glyphs.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")


## Paint the lane number `opts.text` and its arrow onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var paint_color: Color = opts.get("paint_color", ObjectArtRoadGlyphConfig.glyph_color)
	var digits: int = opts.get("digit_scale", ObjectArtRoadGlyphConfig.glyph_digit_scale)
	var middle := int(c.w / 2.0)
	Glyphs.draw_centered(c, String(opts.get("text", "00")), middle, 0, Kit.ink(paint_color, digits))
	var gap: int = opts.get("gap_px", ObjectArtRoadGlyphConfig.glyph_gap_px)
	_arrow(c, Vector2i(middle, Glyphs.text_height(digits) + gap), paint_color, opts)
	Kit.fade(c, opts.get("opacity", ObjectArtRoadGlyphConfig.glyph_opacity))
	Kit.wear(
		c,
		opts.get("wear_chance", ObjectArtRoadGlyphConfig.glyph_wear_chance),
		opts.get("wear_depth", ObjectArtRoadGlyphConfig.glyph_wear_depth),
		opts.get("wear_scratches", ObjectArtRoadGlyphConfig.glyph_wear_scratches),
	)


## An arrow pointing down, its shaft starting at `from` (the shaft's top centre).
static func _arrow(c: PixelCanvas, from: Vector2i, col: Color, opts: Dictionary) -> void:
	var head: int = opts.get("arrow_head", ObjectArtRoadGlyphConfig.glyph_arrow_head)
	var shaft_w: int = opts.get("arrow_shaft_w", ObjectArtRoadGlyphConfig.glyph_arrow_shaft_w)
	var shaft_h: int = opts.get("arrow_shaft_h", ObjectArtRoadGlyphConfig.glyph_arrow_shaft_h)
	Kit.fill_rect(c, Rect2i(from.x - int(shaft_w / 2.0), from.y, shaft_w, shaft_h), col)
	for k in head:
		Kit.fill_rect(
			c,
			Rect2i(from.x - head + k, from.y + shaft_h + k, (head - k) * 2 + 1, 1),
			col,
		)
