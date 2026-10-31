extends GameTest
## DR14 (`docs/doors.md`): a door that cannot open wide enough makes the walk a blocked one, and
## the NPC goes in by the other way.
##
## A hand-laid house: a hall and one bedroom with two ways into it, a hollow door near the defender
## (door A) and a bare doorway further down the wall (B). A chair stands in door A's swing, so the
## leaf stops short against it and cannot open wide enough to pass. One defender stands in the hall
## by door A; the one room left to search is the bedroom. Real Von, the whole pipeline: nothing is
## scripted. The chair is the scenario's premise (what holds the door shut); nothing else is
## changed. The test requires that the defender went to door A and tried it before it asserts that
## it got into the bedroom, through B.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOOR_A := Vector2(400, 120)
const DOOR_A_WIDTH := 80.0
const START := Vector2(250, 120)
const DOOR_A_HINGE := Vector2(400, 86)
const DOORWAY_B := Vector2(400, 320)
## Door A's latch jamb (the south end of its 80 px gap) and how near (px) the defender gets to it
## when it tries the door.
const LATCH_JAMB_A := Vector2(400, 160)
const TRIED_NEAR := 45.0
## The door counts as not open wide enough while it is open less than this (degrees).
const STILL_SHUT := 40.0


func describe() -> Dictionary:
	return {
		"name": "A door that will not open makes the AI go in by the other way",
		"description": "A defender sent to search a bedroom tries the nearer door, which a chair "
			+ "in its swing keeps from opening wide enough, and goes in by the other doorway.",
		"tags": ["ai", "movement", "door", "von"],
		"requires_von": true,
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "bedroom", "type": "bedroom", "rect": BEDROOM },
	], [
		{
			"pos": DOOR_A, "width": DOOR_A_WIDTH,
			"door": {
				"name": "door_a", "material": "hollow", "style": "flush",
				"hinge": DOOR_A_HINGE, "swing_into": Vector2.RIGHT,
			},
		},
		{ "pos": DOORWAY_B, "width": 52.0 },
		{ "pos": Vector2(0, 200), "width": 80.0 },  # the hall's way out to the garden
	])
	# Premise: what holds door A shut is a chair in its swing.
	s.object(&"chair", "chair", Vector2(424, 160))
	s.actor(&"npc", &"defender", START, { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"door_a")
	var npc := t.actor(&"npc")
	var seen := {
		"searched_for": false,
		"tried": false,
		"through_b": false,
		"through_a": false,
		"blocked": false,
	}
	var done := func() -> bool:
		_sample(t, npc, seen)
		return BEDROOM.grow(-20).has_point(npc.global_position)
	await t.until(done, 90.0)
	if not t.require(
			seen["searched_for"],
			"premise: the defender went to search the bedroom (act %s)"
				% Entry.brain(t, &"npc").current_act(),
	):
		return
	if not t.require(
			seen["tried"],
			"the defender tried door A, the nearer way (it never came near its latch jamb %s)"
				% LATCH_JAMB_A,
	):
		return
	t.check(
		door.angle() < STILL_SHUT,
		"premise: the chair kept door A from opening wide enough (%.0f degrees)" % door.angle(),
	)
	t.check(
		seen["blocked"],
		"the walk through door A was a blocked one: the decision re-ran for \"way blocked\"",
	)
	t.check(BEDROOM.has_point(npc.global_position), "the defender got into the bedroom")
	t.check(seen["through_b"], "it went in by the other doorway")
	t.check(not seen["through_a"], "it did not go in through the held door")


## One frame's reads: what the defender is after, whether it has stood by door A's latch, and by
## which doorway it crossed the wall between the rooms.
func _sample(t: TestContext, npc: Node2D, seen: Dictionary) -> void:
	if str(Entry.brain(t, &"npc").current_act()).begins_with("search/"):
		seen["searched_for"] = true
	var state: Dictionary = Entry.brain(t, &"npc").debug_state()
	if String(state.get("decision_reason", "")) == "way blocked":
		seen["blocked"] = true
	var at := npc.global_position
	if at.distance_to(LATCH_JAMB_A) <= TRIED_NEAR:
		seen["tried"] = true
	if absf(at.x - 400.0) < 8.0:
		if absf(at.y - DOORWAY_B.y) < 30.0:
			seen["through_b"] = true
		elif absf(at.y - DOOR_A.y) < 30.0:
			seen["through_a"] = true
