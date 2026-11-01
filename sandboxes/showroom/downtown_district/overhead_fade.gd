extends Node
## Fades an overhead drawing while the player stands inside `zone` (the tower's footprint), the way
## the upper floors of a tower should clear when you walk into its ground floor.

const OPAQUE := 1.0
const FADED := 0.1
## Alpha per second.
const RATE := 3.0

## The drawing to fade, the world rect that clears it and who to watch.
var drawing: CanvasItem
var zone := Rect2()
var player: Node2D


func _process(delta: float) -> void:
	if not is_instance_valid(drawing):
		return
	var inside := is_instance_valid(player) and zone.has_point(player.global_position)
	var alpha := move_toward(drawing.modulate.a, FADED if inside else OPAQUE, RATE * delta)
	drawing.modulate.a = alpha
