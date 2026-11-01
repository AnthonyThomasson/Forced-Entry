extends RefCounted
## The "WIP ELEVATOR LOBBY" floor stencil, painted over a room's real floor (a transparent layer the
## size of the room). Options: `variant` -- `a` worn boxed stencil, the letters inside a painted
## rectangle (The Ascent's "SECURITY CHECK"); `b` large faded room-name letters, no box (Prison
## Architect); `c` a yellow and black hazard-stripe border round the room with stencil letters.

const Glyphs := preload("res://sandboxes/showroom/downtown_district/glyphs.gd")
const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const LINES := ["WIP", "ELEVATOR", "LOBBY"]
const PAINT := Color(0.88, 0.86, 0.76)
const HAZARD := Color(0.96, 0.76, 0.12)
const BLACK := Color(0.06, 0.06, 0.07)
const BORDER := 12
const LINE_GAP := 2


## Paint the stencil for `opts.variant` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("variant", "a")):
		"b":
			_faded(c)
		"c":
			_hazard(c)
		_:
			_boxed(c)


static func _boxed(c: PixelCanvas) -> void:
	var scale := 3
	var box := _text_box(scale).grow(14)
	box.position += Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	Kit.fill_rect(c, box, PAINT)
	Kit.fill_rect(c, box.grow(-5), PixelCanvas.CLEAR)
	_lines(c, scale, PAINT, true)
	Kit.fade(c, 0.9)
	Kit.wear(c, 0.22, 0.95, 14)


static func _faded(c: PixelCanvas) -> void:
	_lines(c, 4, PAINT, false)
	Kit.fade(c, 0.5)
	Kit.wear(c, 0.3, 0.9, 10)


static func _hazard(c: PixelCanvas) -> void:
	var inner := Rect2i(BORDER, BORDER, c.w - BORDER * 2, c.h - BORDER * 2)
	for y in c.h:
		for x in c.w:
			if not inner.has_point(Vector2i(x, y)):
				c.px(x, y, HAZARD if int((x + y) / 7.0) % 2 == 0 else BLACK)
	Kit.frame(c, Rect2i(0, 0, c.w, c.h), BLACK)
	Kit.frame(c, inner.grow(1), BLACK)
	_lines(c, 3, PAINT, true)
	Kit.fade(c, 0.92)
	Kit.wear(c, 0.2, 0.9, 16)


## The two lines of text, centred on the canvas, in `col`.
static func _lines(c: PixelCanvas, scale: int, col: Color, stencil: bool) -> void:
	var box := _text_box(scale)
	var top := int(c.h / 2.0) + box.position.y
	for i in LINES.size():
		var y := top + i * (Glyphs.text_height(scale) + LINE_GAP * scale)
		Glyphs.draw_centered(c, LINES[i], int(c.w / 2.0), y, Kit.ink(col, scale, 0.0, stencil))


## The block both lines make at `scale`, centred on the origin.
static func _text_box(scale: int) -> Rect2i:
	var w := Glyphs.text_width(LINES[1], scale)
	var h := Glyphs.text_height(scale) * LINES.size() + LINE_GAP * scale * (LINES.size() - 1)
	return Rect2i(-int(w / 2.0), -int(h / 2.0), w, h)
