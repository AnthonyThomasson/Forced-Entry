extends RefCounted
## Objects domain (private): a door's damage, `door.damage`: its hit points and the wear on its
## latch. The material's row of `DoorMaterialConfig.materials` says what each kind
## of hit is worth (`factor`) and how much the latch takes.

## The leaf's hit points now and at the start; at 0 it is knocked down.
var hp := 0.0
var max_hp := 0.0
## What is left of the latch (the damage kicks and blasts from the push side may still deal before
## it gives).
var latch := 0.0
## The material's row.
var _row: Dictionary


func _init(row: Dictionary) -> void:
	_row = row
	max_hp = row["hp"]
	hp = max_hp
	latch = row["latch_hp"]


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
