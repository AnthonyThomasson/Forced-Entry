extends Node2D
## Test probe (not a test): a drawn node that joins its group in its own `_ready`, as the game's
## characters, vehicles and grenades do (`tests/art/mirror_mesh_lifecycle_test.gd`).


func _ready() -> void:
	add_to_group(&"fx_probe")
