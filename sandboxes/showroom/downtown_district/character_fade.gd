extends Node
## Fades an overhead drawing while any character's body is under it: the awning and the sign over a
## storefront door clear to a see-through ghost when someone walks beneath, and come back when they
## leave, so you can see who is under them.

const OPAQUE := 1.0
const FADED := 0.25
## Seconds to fade from solid to ghost, and so the alpha per second either way.
const FADE_TIME := 0.15
const RATE := (OPAQUE - FADED) / FADE_TIME

## The drawing to fade and its size: the area it covers is the rect of that size at its position.
var drawing: Node2D
var size := Vector2.ZERO


func _process(delta: float) -> void:
	if not is_instance_valid(drawing):
		return
	var target := FADED if _occupied() else OPAQUE
	drawing.modulate.a = move_toward(drawing.modulate.a, target, RATE * delta)


## Whether a character (any, the player or a walker) is inside the drawing's area.
func _occupied() -> bool:
	var area := Rect2(drawing.global_position, size)
	for body: Node2D in get_tree().get_nodes_in_group(&"characters"):
		if body.visible and area.has_point(body.global_position):
			return true
	return false
