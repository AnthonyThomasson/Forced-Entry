extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The bungalow (seed 8, furnished) doorway from the
## living room into the kitchen, the stack in the living room ordered on its north side: the sweep
## finds the north run 140 px to the room's corner with two pieces against the wall past the first
## slot (-224..-182, -334..-292 and -219..-187, -298..-268), and the south run as short, a piece
## 22 px past the jamb (-223..-187, -118..-46) and another by its end (-220..-184, -43..-9), so a
## single file along that wall would put the second and third slots on the doorway's front and out
## of the room: a short wall and furniture by a doorway (E21, E22).
##
## Seed 8, not seed 1: on seed 1 the furniture leaves slot 4 in a pocket
## whose only way in runs past slot 3's holder, so the member sent there is stopped by its
## teammate. That defect is kept by `ai/entry/stack_slot_reached_through_another` (a `gap` test on
## seed 1), issue #170.
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

const Reach := preload("res://tests/_ai/reach_probe.gd")
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"beyond": "in the room beyond (the kitchen)",
		&"outside": "outside (the street, south of the house)",
}


func describe() -> Dictionary:
	return {
		"name": "An ordered stack at the bungalow's living-room door to the kitchen: every member "
			+ "reaches its slot",
		"description": "4 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	# Doors off until #159 makes this family door-aware.
	s.switch(&"worldgen.doors", false)
	s.house(8, "bungalow")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(-150, -250), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(-150, -100), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(-340, -240), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(100, 90), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(-230, -170), "kitchen"), &"lead", 1, STARTS)
