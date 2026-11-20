extends RefCounted
## Tests: the free pieces of a vision test (plan handles led by 3D bodies): held still, and whether
## they are still moving: `const Held := preload("res://tests/_vision/held_pieces.gd")`.


## Whether the free piece `target` (a plan handle led by a 3D body; anything else is at rest) moves
## faster than `speed` px/s or turns faster than `spin` rad/s.
static func moves_faster(target: Node2D, speed: float, spin: float) -> bool:
	var lead := TwinSpace.leader_of(target)
	if lead == null or lead.sleeping:
		return false
	return lead.call(&"plan_velocity").length() > speed or absf(lead.call(&"plan_spin")) > spin


## Hold every free piece among `targets` still (its 3D body frozen static) or let it go again.
static func hold_still(targets: Array, held: bool) -> void:
	for target: Node2D in targets:
		var lead := TwinSpace.leader_of(target)
		if lead != null:
			lead.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			lead.freeze = held
