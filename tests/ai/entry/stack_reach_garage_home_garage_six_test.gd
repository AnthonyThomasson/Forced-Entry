extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The garage home (seed 1, furnished) doorway from
## the kitchen into the garage, a stack of six in the kitchen ordered on its east side: the sweep
## finds both runs short (150 px to the kitchen's corners) and a piece against the wall at the east
## jamb (568..606, -351..-315), so six cannot stand in one file: the east file skips the piece
## (E22), the rest go west (E21) and then into a second file a step out (E21). Six members, one from
## each starting place.
##
## 6 invaders are ordered (quiet, held for the go so the stack forms and holds) to stack on it from
## the east side through `Squad.issue`, by a puppet leader standing far off; Von is down (scripted),
## the rest of the AI on. Each must end in the slot it claimed (6 px), never take the back of the
## stack or abort, be there within its route's walking time plus 8 s, keep out of the doorway's view
## and off the door's front close in when a way round exists, and never bump a teammate
## (`tests/_ai/reach_probe.gd`). The stack moves up (rule 9): a member's slot may rise only as the
## other half of a teammate's move-up into the slot it held (both radioed as claims), and each
## move-up must be a real one (the mover in its own slot, into a lower one of its file, and ending
## in it).

const Reach := preload("res://tests/_ai/reach_probe.gd")
const IDS := [&"near", &"wrong", &"far", &"beyond", &"far_end", &"outside"]
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"far": "in the same room, far from the door (the kitchen's far corner)",
		&"beyond": "in the room beyond (the garage)",
		&"far_end": "at the far end of the house (the bathroom)",
		&"outside": "outside (the street, south of the house)",
}


func describe() -> Dictionary:
	return {
		"name": "A six-member ordered stack at the garage home's kitchen door to the garage: every "
			+ "member reaches its slot",
		"description": "6 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "garage_home")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(615, -295), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(420, -300), { "max_health": 1_000_000.0 })
	s.actor(&"far", &"invader", Vector2(660, -30), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(380, -470), { "max_health": 1_000_000.0 })
	s.actor(&"far_end", &"invader", Vector2(-160, -560), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(100, 80), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(500, -360), "garage"), &"lead", 1, STARTS)
