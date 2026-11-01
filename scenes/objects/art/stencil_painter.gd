extends RefCounted
## Pixel-art floor STENCIL painter (Objects domain, private): paint on a floor, a transparent layer
## the size of the area it covers. `opts.text` is the words, one to a line, and `opts.style`
## `hazard`: a border of yellow and black stripes round the edge and the words centred inside it in
## stencil letters (the middle of each stem bridged out), the whole faded and worn. The words are
## always drawn upright on the canvas, which is never turned. Knobs:
## ObjectArtStencilConfig.stencil_*, each overridable per stencil by `opts` (keyed without the
## prefix); the painter takes its colours as given (`ObjectArt.AS_GIVEN`).

const Glyphs = preload("res://scenes/objects/art/glyphs.gd")
const Kit = preload("res://scenes/objects/art/paint_kit.gd")


## Paint the stencil of `opts.text` in `opts.style` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var border: int = opts.get("border_px", ObjectArtStencilConfig.stencil_border_px)
	var dark: Color = opts.get("hazard_black", ObjectArtStencilConfig.stencil_hazard_black)
	var inner := Rect2i(border, border, c.w - border * 2, c.h - border * 2)
	_stripes(c, inner, opts)
	Kit.frame(c, Rect2i(0, 0, c.w, c.h), dark)
	Kit.frame(c, inner.grow(1), dark)
	_lines(c, String(opts.get("text", "")).split(" "), inner, opts)
	Kit.fade(c, opts.get("opacity", ObjectArtStencilConfig.stencil_opacity))
	Kit.wear(
		c,
		opts.get("wear_chance", ObjectArtStencilConfig.stencil_wear_chance),
		opts.get("wear_depth", ObjectArtStencilConfig.stencil_wear_depth),
		opts.get("wear_scratches", ObjectArtStencilConfig.stencil_wear_scratches),
	)


## Yellow and black diagonal stripes over everything outside `inner`.
static func _stripes(c: PixelCanvas, inner: Rect2i, opts: Dictionary) -> void:
	var width: float = opts.get("stripe_px", ObjectArtStencilConfig.stencil_stripe_px)
	var colors: Array[Color] = [
		opts.get("hazard_color", ObjectArtStencilConfig.stencil_hazard_color),
		opts.get("hazard_black", ObjectArtStencilConfig.stencil_hazard_black),
	]
	for y in c.h:
		for x in c.w:
			if not inner.has_point(Vector2i(x, y)):
				c.px(x, y, colors[int((x + y) / width) % 2])


## `lines` of text centred in `inner`, one under the next, at the largest scale that fits.
static func _lines(
	c: PixelCanvas,
	lines: PackedStringArray,
	inner: Rect2i,
	opts: Dictionary,
) -> void:
	var margin: int = opts.get("text_margin", ObjectArtStencilConfig.stencil_text_margin)
	var line_gap: int = opts.get("line_gap", ObjectArtStencilConfig.stencil_line_gap)
	var scale := _fit(lines, inner.grow(-margin).size, opts)
	var gap: int = line_gap * scale
	var height := Glyphs.text_height(scale)
	var top := inner.get_center().y - int((height * lines.size() + gap * (lines.size() - 1)) / 2.0)
	var letters: Color = opts.get("paint_color", ObjectArtStencilConfig.stencil_paint_color)
	var ink := Kit.ink(letters, scale, 0.0, true)
	for i in lines.size():
		Glyphs.draw_centered(c, lines[i], inner.get_center().x, top + i * (height + gap), ink)


## The largest scale (down from the `text_scale` knob, at least 1) at which `lines` fit in `room`.
static func _fit(lines: PackedStringArray, room: Vector2i, opts: Dictionary) -> int:
	var line_gap: int = opts.get("line_gap", ObjectArtStencilConfig.stencil_line_gap)
	var largest: int = opts.get("text_scale", ObjectArtStencilConfig.stencil_text_scale)
	for scale in range(largest, 0, -1):
		var widest := 0
		for line in lines:
			widest = maxi(widest, Glyphs.text_width(line, scale))
		var height := (
			Glyphs.text_height(scale) * lines.size() + line_gap * scale * (lines.size() - 1)
		)
		if widest <= room.x and height <= room.y:
			return scale
	return 1
