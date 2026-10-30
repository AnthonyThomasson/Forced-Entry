extends Node2D
## Physics System: draw layer for a debris chip: one small shape (rect/tri/circle) from the chip's
## fields.

## The debris chip (control node).
@onready var _control := get_parent()


func _draw() -> void:
	var color: Color = _control.color
	var s: Vector2 = _control.chip_size
	match _control.chip_shape:
		"circle":
			draw_circle(Vector2.ZERO, s.x * 0.5, color)
		"tri":
			draw_colored_polygon(DebrisLayer.tri(s), color)
		_:  # "rect"
			draw_rect(Rect2(-s * 0.5, s), color)
