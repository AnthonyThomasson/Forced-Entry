extends RefCounted
## A test painter (#193 phase 2b, Character): the vest's front face or its side, alone on a canvas,
## so a test can render it flat and lit (`VestPainter.paint_face` is not a painter of its own: the
## shoulders and the trunk's faces call it). `opts.face` is `"front"` or `"side"`.

const VestPainter := preload("res://scenes/character/body/art/vest_painter.gd")


## Paint the vest's `opts.face` onto `c` (the canvas's height is the trunk's, the waist at its end).
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	VestPainter.paint_face(c, String(opts.get("face", "front")), c.h, opts)
