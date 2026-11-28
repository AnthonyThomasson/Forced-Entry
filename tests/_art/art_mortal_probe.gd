extends Node2D
## Test probe (not a test): a plan handle (`TwinSpace.BODIES`) that can die (it has a `died` signal,
## as a character has), to prove what the mirror does with its mesh when it dies
## (`tests/art/mirror_mesh_lifecycle_test.gd`).

## Never emitted: the mirror only has to see the signal exist, as it does on a character.
@warning_ignore("unused_signal")
signal died


func _init() -> void:
	add_to_group(TwinSpace.BODIES)
