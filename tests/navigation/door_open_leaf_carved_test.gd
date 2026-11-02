extends GameTest
## Issue #183 (`docs/doors.md` DR14, ADR 0010): a door's leaf standing at its open stop is carved
## into the nav maps where it stands, in the room it swings into, and the doorway past it stays
## open; a leaf short of it (shut, ajar) is left out, and paths go through its doorway as if it were
## open.
##
## A hand-laid hall and bedroom, the doorway between them 60 px wide in the wall, its hollow door
## hinged on the north jamb (48 px between the jambs, the narrowest a house has), swinging into the
## bedroom: open, its leaf lies out from the hinge into the bedroom along the wall's normal. Routes
## from the hall to three bedroom points are read on the planning and the steering map with the door
## shut, ajar and open: one behind the leaf (north of it, by the wall), one south of the doorway and
## one in the room's far corner.

const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
const HINGE := Vector2(400, 176)
const FROM := Vector2(300, 200)
## Behind the open leaf, north of it by the doorway's wall.
const BEHIND := Vector2(440, 140)
const SOUTH := Vector2(440, 300)
const FAR := Vector2(660, 40)
## A route longer than this (px) has gone the long way: there is no other way into the bedroom, so
## it is no route through the doorway at all.
const SHORT := 450.0
## A character's body radius (px), the spec's number (DR14).
const BODY_RADIUS := 14.0
## The door's open stop (DR3) and an ajar angle short of it.
const OPEN := 90.0
const AJAR := 45.0


func describe() -> Dictionary:
	return {
		"name": "An open door's leaf is carved into the nav maps, a shut one is not",
		"description": "A door at its open stop is a hole where its leaf stands and its doorway "
			+ "still paths; shut or ajar it is left out and its doorway paths as if open.",
		"tags": ["navigation", "door", "doorway"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "bedroom", "type": "bedroom", "rect": BEDROOM },
	], [{
		"pos": DOORWAY, "width": 60.0,
		"door": {
			"name": "door", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])


func run(t: TestContext) -> void:
	var door: Node = t.object(&"door")
	if not t.require(door != null and door.gap() < 1.0, "the door stands shut in the doorway"):
		return
	var planning: RID = t.world.get_world_2d().navigation_map
	var maps := { "planning": planning, "steering": NavBuilder.steering_map(planning) }
	await t.seconds(0.5)
	_check_through(t, maps, door, "shut", false)
	door.turn_by(AJAR, null)
	await t.seconds(1.5)
	if not t.require(absf(door.angle() - AJAR) < 1.0, "the door stands ajar (%.0f)" % door.angle()):
		return
	_check_through(t, maps, door, "ajar", false)
	door.open_fully(null)
	await t.seconds(1.5)
	if not t.require(door.angle() >= OPEN - 1.0, "the door stands open (%.0f)" % door.angle()):
		return
	_check_through(t, maps, door, "open", true)


## Check every route on every map of `maps` with the door standing `label` (`_check_route`), the
## leaf `carved` or not.
func _check_through(t: TestContext, maps: Dictionary, door: Node, label: String,
		carved: bool) -> void:
	var pose: Transform2D = door.leaf_pose(door.angle())
	var size: Vector2 = door.leaf_size()
	for name in maps:
		for to in [BEHIND, SOUTH, FAR]:
			_check_route(
				t,
				NavBuilder.route(maps[name], FROM, to),
				to,
				"%s door: the %s map" % [label, name],
				[pose, size] if carved else [],
			)


## Check one route `path` to `to` on the map `what` names (with the door's state): it goes through
## the doorway (short); with the leaf carved (`leaf` its pose and size, else empty), it runs no
## nearer than a body's radius to the leaf, and the one behind it goes round its free end.
func _check_route(
	t: TestContext,
	path: PackedVector2Array,
	to: Vector2,
	what: String,
	leaf: Array,
) -> void:
	var length := NavBuilder.path_length(path)
	t.check(
		length < SHORT and path[path.size() - 1].distance_to(to) < 2.0,
		"%s paths through the doorway to %s (%.0f px)" % [what, to, length],
	)
	if leaf.is_empty():
		return
	var pose: Transform2D = leaf[0]
	var size: Vector2 = leaf[1]
	var closest := _closest_to_leaf(path, pose, size)
	t.check(
		closest > BODY_RADIUS,
		"%s route to %s keeps a body off the leaf (%.1f px)" % [what, to, closest],
	)
	if to != BEHIND:
		return
	var free_end: Vector2 = pose * Vector2(size.x * 0.5, 0.0)
	t.check(
		path.size() > 2 and _reaches_past(path, free_end, pose.x.normalized()),
		"%s route behind the leaf goes round its free end %s (%s)"
			% [what, free_end.round(), path],
	)


## The least distance (px) from route `path` to the leaf's rectangle (`size`, centred on `pose`).
static func _closest_to_leaf(path: PackedVector2Array, pose: Transform2D, size: Vector2) -> float:
	var best := INF
	for i in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i])))
		for k in steps + 1:
			best = minf(best, _to_leaf(pose, size, path[i - 1].lerp(path[i], float(k) / steps)))
	return best


## How far `p` is from the leaf's rectangle (`size`, centred on `pose`): 0 inside it.
static func _to_leaf(pose: Transform2D, size: Vector2, p: Vector2) -> float:
	var local: Vector2 = pose.affine_inverse() * p
	var half := size * 0.5
	var on := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return local.distance_to(on)


## Whether some waypoint of `path` stands past the leaf's free end `free_end` along the leaf `along`
## (hinge to free end).
static func _reaches_past(path: PackedVector2Array, free_end: Vector2, along: Vector2) -> bool:
	for p in path:
		if (p - free_end).dot(along) > 0.0:
			return true
	return false
