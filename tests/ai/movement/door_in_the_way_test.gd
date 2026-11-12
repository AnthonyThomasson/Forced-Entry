extends GameTest
## DR14 (`docs/doors.md`): an NPC whose walk leads through a door not open wide enough to pass opens
## it from its latch side, goes in and leaves it open; the room behind a shut door stays unsearched
## until it is open; a second NPC reaching the open door does not shut it.
##
## A hand-laid house: a hall (the exit to the garden on its west wall) and one bedroom behind a
## shut, hollow door in the wall between them, which swings into the bedroom. Two invaders stand in
## the hall; the one room left to search is the bedroom. Recorded Von, the whole pipeline: nothing
## is scripted and no switch is changed. The test requires that the invaders went for the bedroom
## before it asserts what they did at the door.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
## The hinge sits on the north jamb (6 px in from the 52 px gap's edge, where the layout's 12 px
## walls end), so the latch is at the south jamb and its side of the doorway is south.
const HINGE := Vector2(400, 180)
## The latch jamb (the south end of the 52 px gap) and how near (px) the opener stands to it when
## the leaf begins to turn.
const LATCH_JAMB := Vector2(400, 226)
const LATCH_NEAR := 45.0
## The leaf is open to its limit within this many degrees.
const OPEN := 88.0


func describe() -> Dictionary:
	return {
		"name": "The AI opens a shut door in its way",
		"description": "Two invaders in a hall with one unsearched room behind a shut door: the "
			+ "first stops beside the door's latch, opens it fully, goes in and leaves it open; "
			+ "the room is not counted searched while the door is shut; the second leaves it open.",
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
			"pos": DOORWAY, "width": 52.0,
			"door": {
				"name": "bedroom_door", "material": "hollow", "style": "flush",
				"hinge": HINGE, "swing_into": Vector2.RIGHT,
			},
		},
		{ "pos": Vector2(0, 200), "width": 80.0 },  # the hall's way out to the garden
	])
	s.actor(&"first", &"invader", Vector2(250, 200), { "facing": Vector2.RIGHT })
	s.actor(&"second", &"invader", Vector2(150, 260), { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"bedroom_door")
	var first := t.actor(&"first")
	var second := t.actor(&"second")
	var seen := {
		"opener": null, "stood_at": Vector2.INF, "searched_shut": false,
		"shut_after_open": false, "was_open": false, "searched_for": false,
	}
	var done := func() -> bool:
		_sample(t, door, seen, [first, second])
		return BEDROOM.grow(-20).has_point(first.global_position) \
				and BEDROOM.grow(-20).has_point(second.global_position)
	await t.until(done, 70.0)
	if not t.require(
			seen["searched_for"],
			"premise: an invader went to search the bedroom (acts %s, %s)" % [
				Entry.brain(t, &"first").current_act(), Entry.brain(t, &"second").current_act(),
			],
	):
		return
	if not t.require(
			BEDROOM.has_point(first.global_position) or BEDROOM.has_point(second.global_position),
			"an invader got into the bedroom (first at %s, second at %s)"
				% [first.global_position, second.global_position],
	):
		return
	if not t.require(seen["opener"] != null, "the door was opened by one of the invaders"):
		return
	var at: Vector2 = seen["stood_at"]
	t.check(
		at.x < DOORWAY.x and at.y > DOORWAY.y and at.distance_to(LATCH_JAMB) <= LATCH_NEAR,
		"the opener stood in the hall beside the latch jamb %s when the leaf began to turn (at %s)"
			% [LATCH_JAMB, at],
	)
	t.check(
		door.angle() >= OPEN, "the door was left fully open (%.0f degrees)" % door.angle()
	)
	t.check(
		not seen["searched_shut"],
		"the bedroom was not counted searched while the door was shut",
	)
	t.check(not seen["shut_after_open"], "no invader shut the door once it was open")


## One frame's reads: who opened the door and where they stood when the leaf began to turn,
## whether the bedroom counted as searched with the door shut, and whether the door was ever
## turned back from fully open.
func _sample(t: TestContext, door: Node, seen: Dictionary, npcs: Array) -> void:
	var angle: float = door.angle()
	for id in [&"first", &"second"]:
		if str(Entry.brain(t, id).current_act()).begins_with("search/"):
			seen["searched_for"] = true
	if seen["opener"] == null and angle > 1.0:
		var nearest: Node2D = npcs[0]
		for npc: Node2D in npcs:
			var closer := npc.global_position.distance_to(DOORWAY)
			if closer < nearest.global_position.distance_to(DOORWAY):
				nearest = npc
		seen["opener"] = nearest
		seen["stood_at"] = nearest.global_position
	if angle <= 1.0:
		for id in [&"first", &"second"]:
			if Entry.room_status(t, id, BEDROOM) == "searched":
				seen["searched_shut"] = true
	if seen["was_open"] and angle < OPEN - 1.0:
		seen["shut_after_open"] = true
	if angle >= OPEN:
		seen["was_open"] = true
