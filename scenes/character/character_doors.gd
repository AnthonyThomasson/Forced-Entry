class_name CharacterDoors extends RefCounted
## A character's use of doors (`character.gd`'s `doors`, interface 7, `docs/doors.md` DR6 and DR7):
## which standing door is in reach (`door_in_reach`), working it (`use`, `turn`). It takes no input
## events: the human's controller turns the Use key and the wheel into these calls, and an NPC's
## will call them as they are. The door is the Objects domain's `Door` (interface 24), held
## duck-typed. Tuning: `CharacterDoorConfig`.

## The character that uses the doors.
var character: CharacterBody2D


## The doors of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## The standing door nearest the character's aim among those in reach ahead, or null: a door (in the
## group `doors`) not knocked down whose leaf has a point within `CharacterDoorConfig.reach` of the
## body that lies ahead of it (on the side `facing` points to). Of those, the one whose leaf is
## nearest `movement.aim_point`. A dead character reaches nothing.
func door_in_reach() -> Node2D:
	if character.is_dead:
		return null
	var best: Node2D = null
	var best_gap := INF
	for door: Node2D in character.get_tree().get_nodes_in_group(&"doors"):
		if not reaches(door):
			continue
		var aim: Vector2 = character.movement.aim_point
		var gap := _closest_to(door, aim).distance_to(aim)
		if gap < best_gap:
			best = door
			best_gap = gap
	return best


## Whether `door` is in reach ahead: it stands (is not knocked down) and its leaf's nearest point
## to the body is within `CharacterDoorConfig.reach` and on the side `facing` points to. A
## character holding Use on a door asks it of that door, whichever door its aim is nearest by then.
func reaches(door: Node2D) -> bool:
	if character.is_dead or door.is_down():
		return false
	var at := _closest_to(door, character.global_position)
	return (
		at.distance_to(character.global_position) <= CharacterDoorConfig.reach
		and (at - character.global_position).dot(character.facing) > 0.0
	)


## How far (px) `door`'s leaf is from the character's centre, at its nearest point.
func distance_to(door: Node2D) -> float:
	return _closest_to(door, character.global_position).distance_to(character.global_position)


## Use `door` (the door in reach when none is given, a held one that is still `reaches`): an open
## door (or one swinging open) swings shut, a shut or ajar one swings fully open. False when there
## is no such door in reach.
func use(door: Node2D = null) -> bool:
	var target := _target(door)
	if target == null:
		return false
	target.toggle(character)
	return true


## Swing `door` (as `use`: the door in reach when none is given) fully open, never shut: a door that
## is open already, or swinging open, stays so. How an NPC works a door in its way, which a second
## walker reaching it must not shut. False when there is no such door in reach.
func open_fully(door: Node2D = null) -> bool:
	var target := _target(door)
	if target == null:
		return false
	target.open_fully(character)
	return true


## Turn `door` (as `use`) by `steps` notches of the wheel (`DoorConfig.step_degrees` each, positive
## opening, a share of a notch as a trackpad's scroll gives): from where it is heading, between shut
## and fully open, and it stays there. False when there is no such door in reach.
func turn(steps: float, door: Node2D = null) -> bool:
	var target := _target(door)
	if target == null:
		return false
	target.turn_by(steps * DoorConfig.step_degrees, character)
	return true


## The door a call acts on: `door` while it is in reach, else (none given) the door in reach.
func _target(door: Node2D) -> Node2D:
	if door == null:
		return door_in_reach()
	return door if is_instance_valid(door) and reaches(door) else null


## The point of `door`'s leaf (its middle line, hinge to latch, as it stands now) nearest `point`.
func _closest_to(door: Node2D, point: Vector2) -> Vector2:
	var pose: Transform2D = door.leaf_pose(door.angle())
	var half: Vector2 = pose.x * door.leaf_size().x * 0.5
	return Geometry2D.get_closest_point_to_segment(point, pose.origin - half, pose.origin + half)
