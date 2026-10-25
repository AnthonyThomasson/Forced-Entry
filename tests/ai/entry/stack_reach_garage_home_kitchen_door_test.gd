extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The garage home (seed 1, furnished as a match
## furnishes it) doorway from the living room into the kitchen, the stack in the living room,
## ordered on its north side: the sweep finds both runs short (130 px to the room's corners) with
## furniture against the wall by both jambs (a piece at 254..292, -271..-235 at the north jamb, one
## at 252..294, -76..-34 by the south end), so a single file along the wall would climb onto the
## doorway's front and out of the room: a short wall and furniture by a doorway (E21, E22). Every
## spot beside the door against its wall is in another doorway's view (the sweep's `views` way in,
## rule 6): the stack takes the spots seen from the fewest.
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
		"name": "An ordered stack at the garage home's living-room door to the kitchen: every "
			+ "member reaches its slot",
		"description": "4 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "garage_home")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(200, -300), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(230, -130), { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(600, -110), { "max_health": 1_000_000.0 })
	s.actor(&"outside", &"invader", Vector2(450, 80), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(300, -180), "kitchen"), &"lead", -1, STARTS)
