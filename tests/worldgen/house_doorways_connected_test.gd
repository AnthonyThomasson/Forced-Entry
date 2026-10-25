extends GameTest
## Every generated house is walkable and logical: within each room all of its doorways reach one
## another on the baked nav map, each doorway can be passed through, and every room is reachable
## from outside the front entrance; and LayoutRules.check finds nothing illogical in it (front door
## in a living space on the south wall, legal exits and doors, bathrooms are dead ends, no
## pass-through rooms) and it has at most one exit. The layout (rooms, doorways, exits) depends only
## on the plan and the seed's mirror draw, never on the furnishing, so these checks share the houses
## this test builds anyway.

const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
const AGENT_RADIUS := 14.0
## Keeps each house clear of the test arena's own nav region.
const FAR_AWAY := Vector2(5000, 5000)
## How far inside a room a doorway's probe point sits.
const STEP_IN := 30.0
const REACH_TOLERANCE := 6.0


func describe() -> Dictionary:
	return {
		"name": "Every doorway in a generated house is reachable",
		"description": "For every floorplan and several seeds: LayoutRules finds the layout "
			+ "logical, all doorways of a room are mutually reachable, each doorway can be walked "
			+ "through, and every room is reachable from the front entrance.",
		"tags": ["worldgen", "navigation", "house", "doorway", "layout"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## True when the nav map has a path from `a` to (near) `b`.
func _reachable(map: RID, a: Vector2, b: Vector2) -> bool:
	var path := NavigationServer2D.map_get_path(map, a, b, true)
	return not path.is_empty() and path[path.size() - 1].distance_to(b) <= REACH_TOLERANCE


## The point just inside room `rect` from the doorway at `pos`.
func _inside(pos: Vector2, rect: Rect2) -> Vector2:
	var p := pos
	if absf(pos.y - rect.position.y) < 1.0:
		p.y += STEP_IN
	elif absf(pos.y - rect.end.y) < 1.0:
		p.y -= STEP_IN
	elif absf(pos.x - rect.position.x) < 1.0:
		p.x += STEP_IN
	else:
		p.x -= STEP_IN
	return p


## The point just outside the house from the front doorway at `pos` (the nearest room's side).
func _outside(pos: Vector2, rect: Rect2) -> Vector2:
	var inner := _inside(pos, rect)
	return pos + (pos - inner)


func _check_house(t: TestContext, plan: String, house_seed: int) -> void:
	var label := "%s seed %d" % [plan, house_seed]
	var house := WorldGen.generate(house_seed, plan, FAR_AWAY, t.world)
	var rooms := WorldGen.get_rooms(house)
	var openings := WorldGen.get_openings(house)

	# The layout is logical: no LayoutRules violation and at most one exit.
	var problems := LayoutRules.check(rooms, openings)
	t.check(problems.is_empty(), "%s is illogical: %s" % [label, "; ".join(problems)])
	var exits := openings.filter(func(o: Dictionary) -> bool: return o["exit"])
	t.check(exits.size() <= 1, "%s has %d exits" % [label, exits.size()])

	var region := NavBuilder.build(house, rooms, t.world, AGENT_RADIUS)
	var map := t.world.get_world_2d().navigation_map
	# The bake is applied to the shared map a frame or more later, and under load later still: wait
	# until the map answers with this house's navmesh (a query before that reads the old map, or
	# logs an engine error).
	var centre: Vector2 = (rooms[0]["rect"] as Rect2).get_center()
	var synced := func() -> bool:
		return (NavigationServer2D.map_get_iteration_id(map) > 0
				and NavigationServer2D.map_get_closest_point_owner(map, centre) == region.get_rid())
	await t.until(synced, 5.0, "%s: the nav map took in the house's navmesh" % label)

	_check_rooms(t, label, map, rooms, openings)
	_check_passable(t, label, map, openings, _rects_by_key(rooms))
	_check_from_front(t, label, map, openings, _rects_by_key(rooms))

	region.queue_free()
	house.queue_free()
	await t.frames(2)


## Each room's rect by its key.
func _rects_by_key(rooms: Array) -> Dictionary:
	var rect_of := {}
	for room in rooms:
		rect_of[room["key"]] = room["rect"]
	return rect_of


## Per room: every pair of its doorways connects.
func _check_rooms(t: TestContext, label: String, map: RID, rooms: Array, openings: Array) -> void:
	for room in rooms:
		var rect: Rect2 = room["rect"]
		var points: Array = []
		for opening in openings:
			if room["key"] in opening["rooms"]:
				points.append(_inside(opening["pos"], rect))
		_check_pairs(t, label, map, points, room["key"])


## Every pair of `points` (the doorways of room `key`) connects.
func _check_pairs(t: TestContext, label: String, map: RID, points: Array, key: String) -> void:
	for i in points.size():
		for j in range(i + 1, points.size()):
			t.check(
				_reachable(map, points[i], points[j]),
				"%s: doorways %s and %s in %s cannot reach each other"
					% [label, points[i], points[j], key],
			)


## Each doorway is passable from either side.
func _check_passable(
	t: TestContext,
	label: String,
	map: RID,
	openings: Array,
	rect_of: Dictionary,
) -> void:
	for opening in openings:
		var keys: Array = opening["rooms"]
		var a: Vector2
		var b: Vector2
		if keys.size() == 2:
			a = _inside(opening["pos"], rect_of[keys[0]])
			b = _inside(opening["pos"], rect_of[keys[1]])
		else:
			a = _inside(opening["pos"], rect_of[keys[0]])
			b = _outside(opening["pos"], rect_of[keys[0]])
		t.check(_reachable(map, a, b) and _reachable(map, b, a),
			"%s: doorway at %s (%s) cannot be passed through" % [label, opening["pos"], keys])


## Every doorway (so every room) is reachable from outside the front entrance.
func _check_from_front(
	t: TestContext,
	label: String,
	map: RID,
	openings: Array,
	rect_of: Dictionary,
) -> void:
	var sides := _doorway_sides(openings, rect_of)
	for front in openings:
		if not front["front"]:
			continue
		var start := _outside(front["pos"], rect_of[front["rooms"][0]])
		for side: Dictionary in sides:
			t.check(
				_reachable(map, start, side["target"]),
				"%s: doorway at %s into %s is not reachable from the front entrance"
					% [label, side["pos"], side["key"]],
			)


## Each side of every doorway: `{ pos, key, target }`, the doorway, the room on that side and the
## point just inside it.
func _doorway_sides(openings: Array, rect_of: Dictionary) -> Array:
	var sides: Array = []
	for opening in openings:
		for key in opening["rooms"]:
			sides.append({
				"pos": opening["pos"],
				"key": key,
				"target": _inside(opening["pos"], rect_of[key]),
			})
	return sides


func run(t: TestContext) -> void:
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			await _check_house(t, plan, house_seed)
