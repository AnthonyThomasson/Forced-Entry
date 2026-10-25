extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The bungalow (seed 1, furnished) doorway from the
## kitchen into the laundry room, a stack of six in the kitchen ordered on its west side: the sweep
## finds the west run 85 px to the kitchen's corner (room for one) and a row of pieces against the
## wall from the east jamb (-474..-369, -334..-282), so the east file has to skip them (E22) and six
## need the second file (E21). Every spot beside the door against its wall is in another doorway's
## view (the sweep's `views` way in, rule 6): the stack takes the spots seen from the fewest. Six
## members, one from each starting place.
##
## 6 invaders are ordered (quiet, held for the go so the stack forms and holds) to stack on it from
## the west side through `Squad.issue`, by a puppet leader standing far off; Von is down (scripted),
## the rest of the AI on. Each must end in the slot it claimed (6 px), never take the back of the
## stack or abort, be there within its route's walking time plus 8 s, keep out of the doorway's view
## and off the door's front close in when a way round exists, and never bump a teammate
## (`tests/_ai/reach_probe.gd`). The stack moves up (rule 9): a member's slot may rise only as the
## other half of a teammate's move-up into the slot it held (both radioed as claims), and each
## move-up must be a real one (the mover in its own slot, into a lower one of its file, and ending
## in it).

const Reach := preload("res://tests/_ai/reach_probe.gd")
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"far": "in the same room, far from the door",
		&"beyond": "in the room beyond (the laundry room)",
		&"far_end": "at the far end of the house (the bedroom)",
		&"outside": "outside (the street, south of the house)",
}


func describe() -> Dictionary:
	return {
		"name": "A six-member ordered stack at the bungalow's kitchen door to the laundry: every "
			+ "member reaches its slot",
		"description": "6 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "bungalow")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(-620, -280), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(-320, -290), { "max_health": 1_000_000.0 })
	s.actor(&"far", &"invader", Vector2(-300, -120), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(-550, -500), { "max_health": 1_000_000.0 })
	s.actor(&"far_end", &"invader", Vector2(60, -420), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(-400, 90), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(
		t,
		Reach.frame(t, Vector2(-530, -340), "laundry_room"),
		&"lead",
		-1,
		STARTS,
	)
