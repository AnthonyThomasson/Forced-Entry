extends RefCounted
## Shared helpers for the Objects tests that compare a body's colliders with the convex pieces it
## should be rebuilt from (not a test itself):
## `const Colliders := preload("res://tests/_objects/collider_probe.gd")`.


## Whether the colliders `have` are the convex pieces `want`: as many, each with the same points.
static func same_pieces(want: Array, have: Array) -> bool:
	var same := want.size() == have.size()
	for k in mini(want.size(), have.size()):
		same = (same
				and (want[k] as ConvexPolygonShape2D).points
					== (have[k] as ConvexPolygonShape2D).points)
	return same
