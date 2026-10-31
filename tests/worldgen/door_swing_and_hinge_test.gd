extends GameTest
## DR3 (docs/doors.md, issue #21): a door opens one way only. An interior door swings into its more
## private room (a tie: seeded), an exterior door into the house; its hinge sits on the jamb nearer
## that room's corner (a tie: seeded), so the fully open leaf lies along the wall; nothing solid
## (furniture, clutter, the neon tube) stands in its swing arc, a quarter disc the leaf's length;
## and a mirrored plan mirrors its hinges. Read through `WorldGen.get_doors` (the door contract,
## interface 24) over every floorplan, both mirror states, several seeds. The room-type privacy
## order, the hinge's place on the jamb and the leaf's thickness are the spec's, kept here.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
## The leaf is pivoted this far (half its 6 px thickness) off the hinge, into the room.
const PIVOT_OFFSET := 3.0
## How close to the middle of a wall (px) a doorway is a tie between its two jambs.
const TIE_SLACK := 1.0
## A tie can go either of two ways.
const SIDES := 2


func describe() -> Dictionary:
	return {
		"name": "A door swings into its private room, hinged at the corner, clear of furniture",
		"description": "DR3: an interior door swings into its more private room, an exterior "
			+ "door into the house; the hinge is on the jamb nearer that room's corner, so the "
			+ "open leaf lies along the wall; no furniture, clutter or neon tube is in the swing "
			+ "arc; mirrored plans too.",
		"tags": ["worldgen", "house", "doors", "door-swing"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	# What a tie went to, over every house: swing room (index in the opening's rooms) and hinge
	# side (-1 the low jamb, 1 the high one).
	var seen := { "swing": {}, "hinge": {}, "neon": 0, "clutter": 0 }
	for plan_key in HouseDefinitions.get_all():
		var states := {}
		for house_seed in range(1, Houses.SEEDS + 1):
			var built := Houses.generated(t, plan_key, house_seed)
			states[Houses.mirrored(plan_key, built)] = true
			seen["neon"] += Houses.neon_tubes(built).size()
			seen["clutter"] += WorldGen.get_clutter(built).size()
			_check_house(t, "%s seed %d" % [plan_key, house_seed], built, seen)
			built.queue_free()
			await t.frames(1)
		t.check(states.size() == 2, "%s: both mirror states were generated" % plan_key)
	t.check(seen["neon"] > 0 and seen["clutter"] > 0,
			"premise: the houses placed neon tubes and clutter for the arcs to keep clear of")
	t.check(seen["swing"].size() == SIDES, "a swing tie goes to either room over the seeds")
	t.check(seen["hinge"].size() == SIDES, "a hinge tie goes to either jamb over the seeds")


## Every door of one generated house.
func _check_house(t: TestContext, where: String, built: Node2D, seen: Dictionary) -> void:
	var rooms := WorldGen.get_rooms(built)
	var pieces := Houses.footprints(built)
	for entry: Dictionary in WorldGen.get_doors(built):
		var opening: Dictionary = entry["opening"]
		var here := "%s %s" % [where, Houses.label(opening)]
		var into := _check_swing(t, here, entry, rooms, seen)
		var room_rect: Rect2 = Houses.room(rooms, opening["rooms"][into])["rect"]
		_check_hinge(t, here, entry, room_rect, seen)
		_check_arc(t, here, entry, pieces)


## The door swings into the room the spec says; returns the index (in the opening's `rooms`) of the
## room it swings into.
func _check_swing(t: TestContext, where: String, entry: Dictionary, rooms: Array,
		seen: Dictionary) -> int:
	var door: Door = entry["node"]
	var opening: Dictionary = entry["opening"]
	var outward: Array = opening["outward"]
	var into := 0
	for i in outward.size():
		if door.swing_into.is_equal_approx(-(outward[i] as Vector2)):
			into = i
	t.check(door.swing_into.is_equal_approx(-(outward[into] as Vector2)),
			"%s: the door swings along a wall normal, %s" % [where, door.swing_into])
	if outward.size() == 1:
		return 0
	var ranks: Array = Houses.types_of(rooms, opening).map(
		func(type: String) -> int: return Houses.PRIVACY[type])
	if ranks[0] == ranks[1]:
		seen["swing"][into] = true
	else:
		var want := 0 if ranks[0] > ranks[1] else 1
		t.check(into == want, "%s: the door swings into the room %s, the more private one"
				% [where, opening["rooms"][want]])
	return into


## The hinge is on the jamb nearer the swing room's corner (either, in the middle of the wall),
## 6 px in from the gap's edge, and the open leaf lies out from that jamb along the wall.
func _check_hinge(t: TestContext, where: String, entry: Dictionary, room_rect: Rect2,
		seen: Dictionary) -> void:
	var door: Door = entry["node"]
	var opening: Dictionary = entry["opening"]
	var p: Vector2 = opening["pos"]
	var gap: float = opening["width"]
	var into := door.swing_into
	var along := Vector2.RIGHT if into.y != 0.0 else Vector2.DOWN
	var offset := (door.hinge - p).dot(along)
	t.check(is_equal_approx(absf(offset), gap * 0.5 - Houses.WALL_THICKNESS * 0.5)
			and is_zero_approx((door.hinge - p).dot(into)),
			"%s: the hinge %s is on a jamb of the doorway at %s, %s px wide" % [
				where,
				door.hinge,
				p,
				gap,
			])
	var to_low := p.dot(along) - room_rect.position.dot(along)
	var to_high := room_rect.end.dot(along) - p.dot(along)
	var side := signf(offset)
	if absf(to_low - to_high) < TIE_SLACK:
		seen["hinge"][side] = true
	else:
		t.check(side == (-1.0 if to_low < to_high else 1.0),
				"%s: the hinge is on the jamb nearer the room's corner" % where)
	_check_open_leaf(t, where, door, p, side)


## The fully open leaf runs into the room from the hinge, along the wall, on the hinge's side of the
## doorway's middle (`side`, -1 or 1 along the wall).
func _check_open_leaf(t: TestContext, where: String, door: Door, middle: Vector2,
		side: float) -> void:
	var along := Vector2.RIGHT if door.swing_into.y != 0.0 else Vector2.DOWN
	var leaf := door.leaf_pose(door.open_angle)
	t.check(leaf.x.is_equal_approx(door.swing_into)
			and signf((leaf.origin - middle).dot(along)) == side,
			"%s: the open leaf runs into the room from the hinge, along the wall" % where)


## Nothing solid, no clutter and no neon tube is in the swing arc.
func _check_arc(t: TestContext, where: String, entry: Dictionary, pieces: Array) -> void:
	var door: Door = entry["node"]
	var opening: Dictionary = entry["opening"]
	var into := door.swing_into
	var along := (opening["pos"] as Vector2) - door.hinge
	along = along.normalized()
	var pivot := door.hinge + into * PIVOT_OFFSET
	for rect: Rect2 in pieces:
		t.check(not Houses.in_arc(rect, pivot, along, into, door.leaf_size().x),
				"%s: %s is in the door's swing arc" % [where, rect])
