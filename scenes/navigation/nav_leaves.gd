class_name NavLeaves extends RefCounted
## The house doors as the Navigation domain bakes them (`docs/adr/0010-doors-are-driven-bodies-
## left-out-of-the-nav-bake.md`): which bodies are doors, left out of the walls' parse, and the hole
## a door's leaf leaves in the map where it stands once it is open. Read duck-typed through the door
## contract (interface 24), found by the group `doors`, so Navigation imports nothing of the Objects
## domain. `NavBuilder`'s own: its bakes and `furniture_holes` call it.

## How far (degrees) short of its open stop a door's leaf may stand and still be carved (`hole`):
## any further shut, its free end stands across the way past it through the doorway (a 48 px
## doorway, the narrowest: an interior one between its jambs, measured open at 78).
const OPEN_SLACK := 10.0
## Half the thickness (px) of the strip a carved leaf leaves in the map (`hole`): a sliver, so the
## 1 px grid keeps it.
const HALF := 1.0
## The least width (px) the map's way past a carved leaf keeps through its doorway, between the
## bake's clearance off the leaf's strip and off the latch jamb: a doorway narrower than that past
## the open leaf (a 52 px one) is left uncarved, as a door short of its stop is, since the carve
## would seal it.
const MIN_PASS := 4.0


## The doors standing under `house`: the bodies in the group `doors`. A door is a driven body in a
## doorway (a StaticBody2D to the engine's parse), but it opens, so a path goes through its doorway
## as if it were open and the walker deals with the leaf: the walls' parse does not see it
## (`NavSource.walls_of`). Named by group alone, so Navigation imports nothing of the Objects
## domain.
static func doors_of(house: Node2D) -> Array[CollisionObject2D]:
	var doors: Array[CollisionObject2D] = []
	if not house.is_inside_tree():
		return doors
	for node in house.get_tree().get_nodes_in_group(&"doors"):
		if node is CollisionObject2D and house.is_ancestor_of(node):
			doors.append(node)
	return doors


## The holes of `house`'s doors' leaves that stand clear of their doorways (`hole`), appended to
## `out`.
static func append_holes(out: Array, house: Node2D) -> void:
	for door in doors_of(house):
		var leaf := hole(door)
		if not leaf.is_empty():
			out.append(leaf)


## The hole door `door`'s leaf leaves in the map where it stands (a world-space ring), or empty when
## it leaves none. Read through the door contract (interface 24: `is_down()`, `angle()`,
## `open_angle`, `leaf_pose`, `leaf_size`). A fallen door has no collider and leaves none. A leaf
## short of its open stop by more than `OPEN_SLACK` leaves none either: shut or ajar, it stands in
## or across the mouth of its doorway, and carving it would seal the doorway, so the path goes
## through as if open and the walker opens it (`docs/doors.md` DR14). A leaf at its open stop is
## carved as the strip along its middle line, `HALF` each side, not as its footprint grown by
## `NavBuilder.OBSTACLE_MARGIN`: the bake's clearance off that strip is within a few px of what a
## body needs off the leaf's faces, where the grown footprint's would close the way past the leaf
## through a narrow doorway (the leaf's clearance meeting the other jamb's). A doorway whose way
## past the open leaf would keep less than `MIN_PASS` on the map is left uncarved too (`_passes`).
static func hole(door: Node) -> PackedVector2Array:
	if (not door.has_method("leaf_pose") or door.call("is_down")
			or float(door.call("angle")) < float(door.get("open_angle")) - OPEN_SLACK):
		return PackedVector2Array()
	var half_length := (door.call("leaf_size") as Vector2).x * 0.5
	var pose: Transform2D = door.call("leaf_pose", float(door.call("angle")))
	if not _passes(door, pose, half_length):
		return PackedVector2Array()
	return PackedVector2Array([
		pose * Vector2(-half_length, -HALF), pose * Vector2(half_length, -HALF),
		pose * Vector2(half_length, HALF), pose * Vector2(-half_length, HALF),
	])


## Whether the map keeps a way `MIN_PASS` wide past door `door`'s leaf standing at `pose` (its
## middle, `half_length` to each end) through the doorway: the latch jamb (where the shut leaf's
## free end meets it) stands off the leaf's middle line by more than the strip's half, the bake's
## clearance off each side (`NavBuilder.AGENT_RADIUS` + `NavBuilder.WALL_MARGIN`) and `MIN_PASS`.
static func _passes(door: Node, pose: Transform2D, half_length: float) -> bool:
	var latch: Vector2 = (door.call("leaf_pose", 0.0) as Transform2D) * Vector2(half_length, 0.0)
	var across := pose.y.normalized()
	var clearance := NavBuilder.AGENT_RADIUS + NavBuilder.WALL_MARGIN
	return absf((latch - pose.origin).dot(across)) - HALF >= 2.0 * clearance + MIN_PASS
