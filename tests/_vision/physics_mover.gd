extends Node
## Test helper (not a test): moves `body` to `to` once, from its own `_physics_process`, on the
## frame after `arm()`. A node does that in the game (a door swinging, a character walking): the
## physics server is told of the move at the next flush, so a query made later in the same frame
## (the view's, at priority 100) still finds the body where it was.

var body: Node2D
var to := Vector2.ZERO
var _armed := false


func _physics_process(_delta: float) -> void:
	if _armed and is_instance_valid(body):
		_armed = false
		body.global_position = to


## Move `body` to `place` in the next physics frame.
func arm(place: Vector2) -> void:
	to = place
	_armed = true
