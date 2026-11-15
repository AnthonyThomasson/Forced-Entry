extends StaticBody2D
## Test probe (not a test): a body that can die (it has a `died` signal, as a character has) with
## one collision shape, to prove what the mirror does with its mesh when it dies
## (`tests/art/mirror_mesh_lifecycle_test.gd`).

@warning_ignore("unused_signal")
signal died


func _init() -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(20, 20)
	shape.shape = box
	add_child(shape)
