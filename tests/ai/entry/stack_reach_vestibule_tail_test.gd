extends GameTest
## Rule 9 with rule 6's no-wall fallback (ticket #65 round 2, `docs/tactical-entry.md` E20 to E22):
## every member of an ordered stack reaches the slot it claimed, on a way in with no spot against
## the wall. A hand-laid house: a lobby (500 x 300), a vestibule (100 x 100) east of it and an
## office east of that, the vestibule joined to each by an 80 px doorway in the middle of its west
## and east walls, so beside the office door there is 10 px of wall either side. The stack forms in
## the vestibule to go into the office: its open floor (inside its walls, off the door's axis by a
## body, out of both doorways' funnels) holds two, so a stack of 4 has a tail of two that holds in
## the lobby, the room it came by, at its doorway into the vestibule, off that doorway's axis and
## out of its funnel, numbered last (`tests/_ai/slots_probe.gd` judges those spots in the sweep;
## this test judges the members getting there).
##
## 4 invaders in the lobby are ordered (quiet, held for the go so the stack forms and holds) to
## stack on the office door through `Squad.issue`, by a puppet leader standing at the lobby's far
## end; Von is down (scripted), the rest of the AI on. Each must end in the slot it claimed (6 px),
## never take the back of the stack or abort, be there within its route's walking time plus 8 s,
## keep out of the doorway's view and off the door's front close in when a way round exists (here
## none does: the only way into the vestibule faces the office door), and never bump a teammate
## (`tests/_ai/reach_probe.gd`). The stack moves up (rule 9): a member's slot may rise only as the
## other half of a teammate's move-up into the slot it held (both radioed as claims), and each
## move-up must be a real one (the mover in its own slot, into a lower one of its file, and ending
## in it).

const Reach := preload("res://tests/_ai/reach_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
const LOBBY := Rect2(0, 0, 500, 300)
const VESTIBULE := Rect2(500, 100, 100, 100)
const OFFICE := Rect2(600, 0, 400, 300)
const DOOR_LOBBY := Vector2(500, 150)
const DOOR_OFFICE := Vector2(600, 150)
const IDS := [&"near", &"near_south", &"far", &"far_south"]
## Where each member starts.
const STARTS := {
		&"near": "in the lobby, near the vestibule's doorway, north of it",
		&"near_south": "in the lobby, near the vestibule's doorway, south of it",
		&"far": "at the lobby's far end, north",
		&"far_south": "at the lobby's far end, south",
}


func describe() -> Dictionary:
	return {
		"name": "An ordered stack in a vestibule with no wall beside the door: every member "
			+ "reaches its slot, the tail in the lobby",
		"description": "4 invaders ordered to stack (held) on a door whose vestibule has no wall "
			+ "beside it and floor for two: each ends in the slot it claimed (two in the "
			+ "vestibule, the tail in the lobby at its doorway), in time, without taking the "
			+ "back, aborting or bumping (rules 6 and 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "lobby", "type": "living_room", "rect": LOBBY, "floor": "oak_planks" },
		{ "key": "vestibule", "type": "hallway", "rect": VESTIBULE, "floor": "oak_planks" },
		{ "key": "office", "type": "bedroom", "rect": OFFICE, "floor": "oak_planks" },
	], [
		{ "pos": DOOR_LOBBY, "width": 80.0 },
		{ "pos": DOOR_OFFICE, "width": 80.0 },
	])
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(440, 60), { "max_health": 1_000_000.0 })
	s.actor(&"near_south", &"invader", Vector2(440, 250), { "max_health": 1_000_000.0 })
	s.actor(&"far", &"invader", Vector2(90, 60), { "max_health": 1_000_000.0 })
	s.actor(&"far_south", &"invader", Vector2(90, 250), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(40, 150),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, DOOR_OFFICE, "office"), &"lead", 1, STARTS)
	# Rule 6: the vestibule holds two; the other two are the tail, in the lobby at its doorway into
	# the vestibule.
	var inside: Array = []
	var tail: Array = []
	for id in IDS:
		var at := Order.stack_point(t, id)
		if VESTIBULE.grow(-Slots.ROOM_INSET).has_point(at):
			inside.append(id)
		elif (LOBBY.grow(-Slots.ROOM_INSET).has_point(at)
				and at.distance_to(DOOR_LOBBY) <= Slots.TAIL_REACH):
			tail.append(id)
	t.check(
		inside.size() == 2 and tail.size() == 2,
		("two slots in the vestibule and a tail of two in the lobby at its doorway (in the "
				+ "vestibule %s, the tail %s, the slots %s)")
			% [
				str(inside),
				str(tail),
				str(IDS.map(func(id): return Order.stack_point(t, id).round())),
			],
	)
