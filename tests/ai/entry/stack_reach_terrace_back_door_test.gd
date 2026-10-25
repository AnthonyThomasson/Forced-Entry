extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The Terrace house (furnished) back door, an
## exterior door into the kitchen, the stack outside in the back garden on its north side: the open
## garden gives every member a long wall to stack on, so this is the plain case the others are
## measured against, with two starts that have to go round the house to keep out of the door's view
## (the wrong side, south of the door; and the living room at the far end of the house, whose plain
## way is out through the kitchen and the doorway itself).
##
## 4 invaders are ordered (quiet, held for the go so the stack forms and holds) to stack on it from
## the north side through `Squad.issue`, by a puppet leader standing far off; Von is down
## (scripted), the rest of the AI on. Each must end in the slot it claimed (6 px), never take the
## back of the stack or abort, be there within its route's walking time plus 8 s, keep out of the
## doorway's view and off the door's front close in when a way round exists, and never bump a
## teammate (`tests/_ai/reach_probe.gd`). The stack moves up (rule 9): a member's slot may rise only
## as the other half of a teammate's move-up into the slot it held (both radioed as claims), and
## each move-up must be a real one (the mover in its own slot, into a lower one of its file, and
## ending in it).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Reach := preload("res://tests/_ai/reach_probe.gd")
## Where each member starts.
const STARTS := {
		&"near": "outside, near along the wall, on the order's side",
		&"wrong": "outside, on the wrong side of the door",
		&"beyond": "in the room beyond (the kitchen)",
		&"far_end": "at the far end of the house (the living room)",
}


func describe() -> Dictionary:
	return {
		"name": "An ordered stack at the Terrace back door: every member reaches its slot",
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
	s.actor(&"near", &"invader", Vector2(900, 60), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(960, 420), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(700, 300), { "max_health": 1_000_000.0 })
	s.actor(&"far_end", &"invader", Vector2(150, 220), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(1400, 800),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(840, 190), "kitchen"), &"lead", 1, STARTS)
