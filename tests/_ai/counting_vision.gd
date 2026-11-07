extends "res://scenes/ai/perception/agent_vision.gd"
## Sight that counts the rays cast through it: the work a decision fast path saves, for a test to
## compare against the plain computation (not a test itself).

## Rays cast so far.
var rays := 0


## The ray, counted.
func raycast(
	space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array,
) -> Dictionary:
	rays += 1
	return super.raycast(space, from, to, exclude)
