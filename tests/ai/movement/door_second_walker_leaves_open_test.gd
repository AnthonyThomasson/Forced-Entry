extends GameTest
## DR14 (`docs/doors.md`): an NPC uses a door in its way until it is fully open, never as a toggle,
## so a second NPC reaching it while the first has it swinging open does not shut it.
##
## The hand-laid house of `door_in_the_way`: a hall and a bedroom behind a shut hollow door that
## swings into the bedroom. Two defenders stand side by side near the door, so that both walk to it
## to search the bedroom (the one room left) and the second arrives while the first has the leaf
## turning. Real Von, the whole pipeline: nothing is scripted and no switch is changed. The test
## requires that the second one reached the door before it was fully open before it asserts that the
## leaf never turned back toward shut.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
const HINGE := Vector2(400, 180)
## The leaf is open to its limit within this many degrees.
const OPEN := 88.0
## The leaf turning back by more than this (degrees) in a frame counts as swinging shut.
const TURNED_BACK := 0.5
## The second walker has come to the door when it is within this many px of it.
const AT_THE_DOOR := 80.0


func describe() -> Dictionary:
	return {
		"name": "A second NPC at an opened door does not shut it",
		"description": "Two defenders sent to search a bedroom behind a shut door: the first opens "
			+ "it, the second reaches it while it swings, and it goes on to stand fully open.",
		"tags": ["ai", "movement", "door", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "bedroom", "type": "bedroom", "rect": BEDROOM },
	], [
		{
			"pos": DOORWAY, "width": 52.0,
			"door": {
				"name": "bedroom_door", "material": "hollow", "style": "flush",
				"hinge": HINGE, "swing_into": Vector2.RIGHT,
			},
		},
		{ "pos": Vector2(0, 200), "width": 80.0 },  # the hall's way out to the garden
	])
	s.actor(&"first", &"defender", Vector2(330, 185), { "facing": Vector2.RIGHT })
	s.actor(&"second", &"defender", Vector2(330, 225), { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"bedroom_door")
	var first := t.actor(&"first")
	var second := t.actor(&"second")
	var seen := { "second_came_while_turning": false, "turned_back": false, "last": 0.0 }
	var done := func() -> bool:
		_sample(door, second, seen)
		return BEDROOM.grow(-20).has_point(first.global_position) \
				and BEDROOM.grow(-20).has_point(second.global_position)
	await t.until(done, 50.0)
	if not t.require(
			str(Entry.brain(t, &"first").current_act()).begins_with("search/")
			or str(Entry.brain(t, &"second").current_act()).begins_with("search/"),
			"premise: the defenders went to search the bedroom (acts %s, %s)" % [
				Entry.brain(t, &"first").current_act(), Entry.brain(t, &"second").current_act(),
			],
	):
		return
	if not t.require(
			seen["second_came_while_turning"],
			"premise: the second defender reached the door before it was fully open",
	):
		return
	t.check(not seen["turned_back"], "the leaf never turned back toward shut")
	t.check(door.angle() >= OPEN, "the door stands fully open (%.0f degrees)" % door.angle())
	t.check(
		BEDROOM.has_point(first.global_position) and BEDROOM.has_point(second.global_position),
		"both defenders got into the bedroom",
	)


## One frame's reads: whether the second walker is at the door while the leaf is swinging, and
## whether the leaf turned back toward shut.
func _sample(door: Node, second: Node2D, seen: Dictionary) -> void:
	var angle: float = door.angle()
	if angle > 1.0 and angle < OPEN and second.global_position.distance_to(DOORWAY) <= AT_THE_DOOR:
		seen["second_came_while_turning"] = true
	if angle < float(seen["last"]) - TURNED_BACK:
		seen["turned_back"] = true
	seen["last"] = angle
