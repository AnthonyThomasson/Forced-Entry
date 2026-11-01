extends GameTest
## A house or tower plan can be turned in quarter turns (clockwise on screen: a south front faces
## west, north, east) after its mirror, and built with or without its street. For a tower and a
## house plan turned 1, 2 and 3 times, over several seeds: the rooms are still axis-aligned rects of
## the plan's size (swapped for an odd turn) and keep their places relative to one another turned
## the same way, the front doorway's `outward` is the turned direction, every doorway is cut into
## the wall of
## each room it opens, every doorway that has a door has one built, and the furniture stays inside
## its room. With `street` off a house has no street ring and no lamps; by default it has both.
## Validation stays plan-local, so a turned house builds with no warning.

const FAR_AWAY := Vector2(5000, 5000)
const PLANS := ["food_hall_tower", "corner_flat"]
const SEEDS := [1, 2, 3, 4]
## Where the plan's south front faces after 0, 1, 2 and 3 clockwise quarter turns.
const FRONT_OUTWARD := [Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2.RIGHT]
## How near a rotated offset must be to the turned room's (single-precision rotation by hand).
const ROTATE_TOLERANCE := 0.5
## A doorway's gap is cut this close to its width.
const CUT_TOLERANCE := 1.5


func describe() -> Dictionary:
	return {
		"name": "A house or tower turns in quarter turns and may skip its street",
		"description": "A tower and a house plan turned 1, 2 and 3 times: rooms keep their size "
			+ "and relative places turned, the front faces the turned way, walls are cut at every "
			+ "doorway, doors are built and furniture stays in its rooms; the street switch "
			+ "leaves out the street ring and lamps.",
		"tags": ["worldgen", "house", "tower", "turn", "street"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## A house of `plan` from `house_seed`, turned `turn` quarter turns.
func _build(t: TestContext, plan: String, house_seed: int, options: Dictionary) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	return HouseSpawner.spawn(plan, FAR_AWAY, rng, t.world, options)


## The room of `rooms` keyed `key`.
func _room(rooms: Array, key: String) -> Dictionary:
	for room: Dictionary in rooms:
		if room["key"] == key:
			return room
	return {}


func _check_turn(t: TestContext, plan: String, house_seed: int, turn: int) -> void:
	var label := "%s seed %d turned %d" % [plan, house_seed, turn]
	var base := _build(t, plan, house_seed, {})
	var turned := _build(t, plan, house_seed, { "turn": turn })
	if not t.require(turned != null and base != null, "%s builds" % label):
		return
	var base_rooms := WorldGen.get_rooms(base)
	var rooms := WorldGen.get_rooms(turned)
	_check_rooms(t, label, base_rooms, rooms, turn)
	_check_openings(t, label, WorldGen.get_openings(base), WorldGen.get_openings(turned), turn)
	_check_walls(t, label, turned, rooms, WorldGen.get_openings(turned))
	_check_doors(t, label, turned)
	_check_furniture(t, label, turned, rooms)
	base.queue_free()
	turned.queue_free()


## The turned rooms: each the base room's size (swapped for an odd turn), and the offset between
## any room's centre and the first's turned as the plan is.
func _check_rooms(t: TestContext, label: String, base: Array, rooms: Array, turn: int) -> void:
	t.check(rooms.size() == base.size(), "%s keeps its %d rooms" % [label, base.size()])
	var anchor_base: Vector2 = (base[0]["rect"] as Rect2).get_center()
	var anchor: Vector2 = (_room(rooms, base[0]["key"])["rect"] as Rect2).get_center()
	for room: Dictionary in base:
		var turned := _room(rooms, room["key"])
		if not t.check(not turned.is_empty(), "%s keeps room %s" % [label, room["key"]]):
			continue
		var was: Rect2 = room["rect"]
		var now: Rect2 = turned["rect"]
		var size := was.size if turn % 2 == 0 else Vector2(was.size.y, was.size.x)
		t.check(
			now.size.is_equal_approx(size),
			"%s: %s is %s, not %s" % [label, room["key"], now.size, size],
		)
		var offset := was.get_center() - anchor_base
		var expected := offset.rotated(turn * PI * 0.5)
		t.check(
			(now.get_center() - anchor).distance_to(expected) < ROTATE_TOLERANCE,
			"%s: %s sits at %s from the first room, not %s"
				% [label, room["key"], now.get_center() - anchor, expected],
		)


## The doorways: the same rooms in the same order, the front facing the turned way.
func _check_openings(
	t: TestContext,
	label: String,
	base: Array,
	openings: Array,
	turn: int,
) -> void:
	if not t.check(
		openings.size() == base.size(),
		"%s keeps its %d doorways" % [label, base.size()],
	):
		return
	for i in openings.size():
		t.check(
			openings[i]["rooms"] == base[i]["rooms"] and openings[i]["front"] == base[i]["front"],
			"%s: doorway %d opens %s, not %s" % [label, i, openings[i]["rooms"], base[i]["rooms"]],
		)
		if openings[i]["front"]:
			t.check(
				(openings[i]["outward"] as Array)[0] == FRONT_OUTWARD[turn],
				"%s: the front faces %s, not %s"
					% [label, (openings[i]["outward"] as Array)[0], FRONT_OUTWARD[turn]],
			)


## Each doorway is a gap in the wall of every room it opens: no wall segment crosses its centre
## and a segment ends half its width to each side.
func _check_walls(
	t: TestContext,
	label: String,
	house: Node2D,
	rooms: Array,
	openings: Array,
) -> void:
	for opening: Dictionary in openings:
		for key: String in opening["rooms"]:
			var wall := house.get_node_or_null(NodePath((key as String).capitalize())) as Node2D
			if not t.check(wall != null, "%s has a wall for %s" % [label, key]):
				continue
			_check_gap(t, "%s: %s" % [label, key], wall, opening)
	t.check(not rooms.is_empty(), "%s has rooms" % label)


## The wall `wall`'s gap at `opening`: nothing crosses its centre, and a wall ends `width / 2` off
## it on each side.
func _check_gap(t: TestContext, label: String, wall: Node2D, opening: Dictionary) -> void:
	var pos: Vector2 = opening["pos"]
	var half: float = opening["width"] * 0.5
	var ends := 0
	for seg: PackedVector2Array in wall.wall_segments():
		var a: Vector2 = wall.global_position + seg[0]
		var b: Vector2 = wall.global_position + seg[1]
		var nearest := Geometry2D.get_closest_point_to_segment(pos, a, b)
		t.check(
			nearest.distance_to(pos) > CUT_TOLERANCE,
			"%s: a wall crosses the doorway at %s" % [label, pos],
		)
		for end in [a, b]:
			if absf(pos.distance_to(end) - half) <= CUT_TOLERANCE:
				ends += 1
	t.check(
		ends == 2,
		"%s: the doorway at %s is cut %d walls' ends wide, not 2" % [label, pos, ends],
	)


## A door stands in every doorway that says so, and the front and exits always have one.
func _check_doors(t: TestContext, label: String, house: Node2D) -> void:
	var doors := WorldGen.get_doors(house)
	var with_door := WorldGen.get_openings(house).filter(
		func(o: Dictionary) -> bool: return o["door"],
	)
	t.check(
		doors.size() == with_door.size(),
		"%s builds %d doors for %d doorways" % [label, doors.size(), with_door.size()],
	)
	for built: Dictionary in doors:
		var door := built["node"] as Node2D
		var opening: Dictionary = built["opening"]
		t.check(
			door.global_position.distance_to(opening["pos"]) <= float(opening["width"]),
			"%s: the door at %s is far from its doorway" % [label, door.global_position],
		)
	for opening: Dictionary in WorldGen.get_openings(house):
		if opening["front"] or opening["exit"]:
			t.check(
				opening["door"],
				"%s: the exterior doorway at %s has no door" % [label, opening["pos"]],
			)


## Every piece of furniture and clutter lies wholly inside the room whose node holds it.
func _check_furniture(t: TestContext, label: String, house: Node2D, rooms: Array) -> void:
	var checked := 0
	for room: Dictionary in rooms:
		var node_name := (room["key"] as String).capitalize() + " Furniture"
		var holder := house.get_node_or_null(NodePath(node_name))
		if holder == null:
			continue
		for piece in holder.get_children():
			var body := piece as RigidBody2D
			if body == null:
				continue
			var footprint := Rect2(body.global_position - body.size * 0.5, body.size)
			checked += 1
			t.check(
				(room["rect"] as Rect2).encloses(footprint),
				"%s: %s at %s is outside %s" % [
					label,
					body.name,
					body.global_position,
					room["key"],
				],
			)
	t.check(checked > 0, "%s has furniture to check" % label)


## The street switch: a house has a street ring and lamps unless built with `street` off.
func _check_street(t: TestContext, plan: String) -> void:
	var with_street := _build(t, plan, 1, {})
	var without := _build(t, plan, 1, { "street": false })
	t.check(not WorldGen.get_street(with_street).is_empty(), "%s has a street by default" % plan)
	t.check(not WorldGen.get_streetlights(with_street).is_empty(), "%s has lamps by default" % plan)
	t.check(WorldGen.get_street(without).is_empty(), "%s has no street with it off" % plan)
	t.check(WorldGen.get_streetlights(without).is_empty(), "%s has no lamps with it off" % plan)
	t.check(
		without.get_node_or_null("Street Lamps") == null,
		"%s has no lamps node with it off" % plan,
	)
	t.check(
		WorldGen.get_rooms(without) == WorldGen.get_rooms(with_street),
		"%s has the same rooms with the street off" % plan,
	)
	with_street.queue_free()
	without.queue_free()


func run(t: TestContext) -> void:
	for plan in PLANS:
		for house_seed in SEEDS:
			for turn in [1, 2, 3]:
				_check_turn(t, plan, house_seed, turn)
		_check_street(t, plan)
	await t.frames(2)
