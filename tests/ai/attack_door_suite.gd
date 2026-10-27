extends UnitSuite
## Native unit suite (pure logic) for the attack doorway (`scenes/ai/team/attack_door.gd`,
## the defenders' ambush rule, #128): from the room a threat is in (outside the house counting as a
## room its exterior doors join), the shortest way doorway to doorway to the leader's room, the cost
## being the straight walk from the threat through each doorway in turn; the last doorway on it is
## the one the crew ambushes. Beneath the crew's simulation tests
## (`ai/combat/crew_ambush_attack_door`, `ai/investigate/crew_ambush_before_contact`, ADR-0002). Fed
## plain room and doorway dicts, the shapes `WorldGen.get_rooms` / `get_openings` give (interface
## 1): the Terrace house of the AI tests, its numbers this suite's own copy. The expected doorways
## are read off the house's plan and the distances worked out by hand in each case's comment, never
## the way the code does.

const AttackDoor := preload("res://scenes/ai/team/attack_door.gd")
const LIVING := Rect2(0, 0, 480, 360)
const KITCHEN := Rect2(480, 0, 360, 360)
const HALL := Rect2(0, 360, 840, 110)
## The doorways, by the id a doorway's centre gives it (`door_<x>_<y>`).
const LIVING_KITCHEN := "door_480_150"
const HALL_LIVING := "door_150_360"
const HALL_KITCHEN := "door_690_360"
const FRONT := "door_0_415"
const BACK := "door_840_190"


func _rooms() -> Array:
	return [
		{ "key": "living_room", "type": "living_room", "rect": LIVING },
		{ "key": "kitchen", "type": "kitchen", "rect": KITCHEN },
		{ "key": "hall", "type": "hallway", "rect": HALL },
	]


func _openings() -> Array:
	return [
		_door(Vector2(480, 150), 90.0, ["living_room", "kitchen"]),
		_door(Vector2(150, 360), 80.0, ["hall", "living_room"]),
		_door(Vector2(690, 360), 80.0, ["hall", "kitchen"]),
		_door(Vector2(0, 415), 80.0, ["hall"], true),
		_door(Vector2(840, 190), 90.0, ["kitchen"], false, true),
	]


func _door(pos: Vector2, width: float, rooms: Array, front := false, exit := false) -> Dictionary:
	return { "pos": pos, "width": width, "rooms": rooms, "front": front, "exit": exit }


func _attack(point: Vector2, leader_room: String) -> String:
	return AttackDoor.doorway(point, leader_room, _rooms(), _openings())


func test_outside_by_the_front_door_comes_through_the_hall() -> void:
	# From 100 px west of the front door: in by it (100), then across the hall to the living room's
	# doorway (about 160) is the short way; round by the back door is over 940 to its door alone.
	assert_str(_attack(Vector2(-100, 415), "living_room")).override_failure_message(
		"a threat outside the front door comes into the living room by the hall's doorway",
	).is_equal(HALL_LIVING)
	# The same threat against a leader in the kitchen: in by the front door (100), across the hall
	# to the living room's doorway (about 160) and on to the kitchen's (about 391) is about 651;
	# along the hall to the kitchen's own doorway (about 692) is about 792, the back door 966 alone.
	# The walk counts, not how many doorways.
	assert_str(_attack(Vector2(-100, 415), "kitchen")).override_failure_message(
		"and into the kitchen through the living room, the shorter walk",
	).is_equal(LIVING_KITCHEN)
	# From the hall's east end the kitchen's own doorway is about 81 away.
	assert_str(_attack(Vector2(750, 415), "kitchen")).override_failure_message(
		"a threat in the hall's east end comes into the kitchen by the hall's kitchen doorway",
	).is_equal(HALL_KITCHEN)


func test_outside_by_the_back_door_comes_through_the_kitchen() -> void:
	# From 100 px east of the back door: in by it (100), then the kitchen's doorway into the living
	# room (about 363), against about 966 to the front door alone.
	assert_str(_attack(Vector2(940, 190), "living_room")).override_failure_message(
		"a threat outside the back door comes into the living room through the kitchen",
	).is_equal(LIVING_KITCHEN)
	assert_str(_attack(Vector2(940, 190), "kitchen")).override_failure_message(
		"and into the kitchen by the back door itself",
	).is_equal(BACK)


func test_room_to_room_takes_the_shortest_walk_not_the_shared_doorway() -> void:
	# From the kitchen the one doorway into the living room is the shared one.
	assert_str(_attack(Vector2(700, 100), "living_room")).override_failure_message(
		"a threat in the kitchen comes into the living room by their doorway",
	).is_equal(LIVING_KITCHEN)
	# From the hall's west end its own doorway into the living room (about 160) is the short way.
	assert_str(_attack(Vector2(300, 415), "living_room")).override_failure_message(
		"a threat in the hall's west end comes by the hall's doorway",
	).is_equal(HALL_LIVING)
	# From the hall's east end: the hall's own doorway is about 453 away, through the kitchen about
	# 105 + 297 = 402, so the way in is the kitchen's doorway, though the hall joins the living
	# room.
	assert_str(_attack(Vector2(600, 415), "living_room")).override_failure_message(
		"a threat in the hall's east end comes round through the kitchen, the shorter walk",
	).is_equal(LIVING_KITCHEN)


func test_a_threat_in_the_leaders_room_names_no_doorway() -> void:
	assert_str(_attack(Vector2(200, 200), "living_room")).override_failure_message(
		"the fight is already inside the leader's room: no doorway",
	).is_empty()


func test_a_leader_in_no_room_names_no_doorway() -> void:
	assert_str(_attack(Vector2(700, 100), "")).override_failure_message(
		"a leader outside every room has no doorway to ambush",
	).is_empty()


func test_a_house_with_no_way_through_names_no_doorway() -> void:
	# The living room with no doorway at all: nothing joins it to the kitchen nor to the outside.
	var openings := _openings().filter(
		func(o): return not (o["rooms"] as Array).has("living_room"),
	)
	assert_int(openings.size()).override_failure_message("premise: two doorways dropped")\
		.is_equal(3)
	assert_str(AttackDoor.doorway(Vector2(700, 100), "living_room", _rooms(), openings))\
		.override_failure_message("no way from the kitchen into a room with no doorway").is_empty()
	assert_str(AttackDoor.doorway(Vector2(-100, 415), "living_room", _rooms(), openings))\
		.override_failure_message("nor from outside").is_empty()
