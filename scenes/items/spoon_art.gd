class_name SpoonArt extends ItemArt
## Items domain: how a grenade's spoon is drawn, a `GrenadeSpoon`'s `art` part: a small metal lever
## lying on the floor. It is never held, so it draws nothing in a hand.

const SpoonPainter = preload("res://scenes/items/art/spoon_painter.gd")
## The spoon's footprint lying flat (px): across, along.
const SIZE := Vector2(3.0, 8.0)
## Its painter's options: painted in metal (`PixelArt`'s `material`).
const METAL := { "material": "metal" }


## The spoon lying on the floor, centered at `at` along `angle`, tinted by `modulate`.
func draw_dropped(canvas: CanvasItem, at: Vector2, angle: float, modulate: Color = Color.WHITE,
		_opts: Dictionary = {}) -> void:
	var turn := angle - PI * 0.5
	var tex := PixelArt.render_turned(
		SpoonPainter,
		SIZE,
		Color(0.62, 0.64, 0.68),
		PixelArt.snap_angle(turn),
		METAL,
	)
	_note_drawn(tex)
	canvas.draw_set_transform(at, turn, Vector2.ONE)
	canvas.draw_texture_rect(tex, Rect2(-SIZE * 0.5, SIZE), false, modulate)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
