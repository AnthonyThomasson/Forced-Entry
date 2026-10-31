extends RefCounted
## Objects domain (private): a door's damage, `door.damage`: its hit points, the wear on its latch
## and what struck it last. The material's row of `DoorMaterialConfig.materials` says what each kind
## of hit is worth (`factor`) and how much the latch takes. A kick shoves the door and then hurts it
## in one strike (`body_strike.gd`), so a shove remembered for the physics frame it came in tells
## the damage that follows it which it was.

## The leaf's hit points now and at the start; at 0 it is knocked down.
var hp := 0.0
var max_hp := 0.0
## What is left of the latch (the damage kicks and blasts from the push side may still deal before
## it gives).
var latch := 0.0
## The material's row.
var _row: Dictionary
## The last shove and the physics frame it came in.
var _push := Vector2.ZERO
var _push_frame := -1


func _init(row: Dictionary) -> void:
	_row = row
	max_hp = row["hp"]
	hp = max_hp
	latch = row["latch_hp"]


## Remember a shove of `impulse` landing this physics frame.
func note_push(impulse: Vector2) -> void:
	_push = impulse
	_push_frame = Engine.get_physics_frames()


## The shove that came in this physics frame, or zero.
func push() -> Vector2:
	return _push if _push_frame == Engine.get_physics_frames() else Vector2.ZERO


## Whether the strike being dealt now is a kick: its shove, this frame, was as hard as
## `DoorConfig.burst_impulse` (a punch's and a walking push's are not).
func kicked() -> bool:
	return push().length() >= DoorConfig.burst_impulse


## The share of a hit's damage of `kind` (`round`, `melee`, `kick`, `blast`) that comes off the hit
## points.
func factor(kind: StringName) -> float:
	return float(_row["%s_factor" % kind])


## Whether a hit of `kind` can wear the latch (a blast does; a boot cannot move a steel door's
## bolt).
func wears_latch(kind: StringName) -> bool:
	return kind == &"blast" or (kind == &"kick" and bool(_row["kicks_latch"]))


## Take `amount` off the hit points; true when none are left.
func hurt(amount: float) -> bool:
	hp = maxf(hp - amount, 0.0)
	return hp <= 0.0


## Wear the latch by `amount`; true when it has given.
func wear(amount: float) -> bool:
	latch = maxf(latch - amount, 0.0)
	return latch <= 0.0
