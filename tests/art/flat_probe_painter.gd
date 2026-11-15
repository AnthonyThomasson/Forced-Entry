extends RefCounted
## A painter for `flat_paint_albedo_test.gd` that uses every light-driven primitive: a bevelled,
## cast-shadowed, glazed block with a glowing dot. Lit, its edge pixels differ from `base`; flat,
## the block is `base` everywhere but the finish and the glowing dot.


static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var tall := PixelShape.rounded(Rect2i(2, 2, c.w - 4, c.h - 4), 3)
	c.fill(tall, base, 6)
	c.fill(PixelShape.rounded(Rect2i(c.w - 6, c.h - 6, 4, 4), 1), base, 2)
	c.bevel(tall, 1, 2, base.lightened(0.4), base.darkened(0.4))
	c.bevel_relative(tall, 3, 3, 0.2, 0.2)
	c.surface(tall, material, base)
	c.cast_shadows()
	c.glowing(func() -> void: c.px(4, 4, Color(1.0, 0.9, 0.2), 6))
