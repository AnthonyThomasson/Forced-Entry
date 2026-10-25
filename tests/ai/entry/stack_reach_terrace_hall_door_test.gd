extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The Terrace house (furnished) doorway from the
## living room into the hall, the stack in the living room, ordered on its west side: the sweep
## (stack_slots_sweep) finds the west run short (110 px to the corner) with the armchair against the
## wall at the jamb (49..111, 279..341), so a single file along that wall would snap onto the
## doorway's front and onto each other: a short wall and furniture by a doorway (E21, E22).
##
## 4 invaders are ordered (quiet, held for the go so the stack forms and holds) to stack on it from
## the west side through `Squad.issue`, by a puppet leader standing far off; Von is down (scripted),
## the rest of the AI on. Each must end in the slot it claimed (6 px), never take the back of the
## stack or abort, be there within its route's walking time plus 8 s, keep out of the doorway's view
## and off the door's front close in when a way round exists, and never bump a teammate
## (`tests/_ai/reach_probe.gd`). The stack moves up (rule 9): a member's slot may rise only as the
## other half of a teammate's move-up into the slot it held (both radioed as claims), and each
## move-up must be a real one (the mover in its own slot, into a lower one of its file, and ending
## in it).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Reach := preload("res://tests/_ai/reach_probe.gd")
const IDS := [&"near", &"wrong", &"beyond", &"outside"]
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"beyond": "in the room beyond (the hall)",
		&"outside": "outside (the back garden)",
}


func describe() -> Dictionary:
	return {
		"name": "An ordered stack at the Terrace living-room door to the hall: every member "
			+ "reaches its slot",
		"description": "4 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, true)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(60, 220), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(330, 290), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(330, 420), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(1000, 100), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(150, 360), "hall"), &"lead", 1, STARTS)
