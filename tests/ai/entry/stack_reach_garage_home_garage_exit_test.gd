extends GameTest
## Rule 9 (ticket #65 round 2, `docs/tactical-entry.md` E1, E2, E18 and E20 to E22): every member of
## an ordered stack reaches the slot it claimed. The garage home (seed 1, furnished) garage exit, an
## exterior door in the house's north wall, the stack outside ordered on its east side: the wall
## runs 150 px east to the house's north-east corner, so a stack of four there runs out of wall at
## the corner and must not go round it (E20, E21): the extras go to the west side, along the long
## north wall.
##
## 4 invaders are ordered (quiet, held for the go so the stack forms and holds) to stack on it from
## the east side through `Squad.issue`, by a puppet leader standing far off; Von is down (scripted),
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
		&"near": "outside, near along the wall, on the order's side",
		&"wrong": "outside, on the wrong side of the door",
		&"beyond": "in the room beyond (the garage)",
		&"far_end": "at the far end of the house (the living room)",
}
## `wrong` walks the long way round the house (west, then along its south wall past the front door
## `door_0_0`, east). The move-up of the member behind it (about 12 s in) re-claims its slot; if
## that lands while it is crossing the front door's view (x -94 to 94 on the wall's south side) the
## entry guard secures that door and the member gives its claim up (E15). Where it stands when the
## move-up comes is a matter of a few px of the walk (the 4 px nav mesh runs its lanes 1 to 2 px off
## the old mesh's). Measured by start x (step 20): 60 to 260 pass, 280 to 320 fail (the member is
## across the view when the move-up lands): 240 stands in the passing band, 40 px from the failing
## starts.
const WRONG_START := Vector2(240, -830)


func describe() -> Dictionary:
	return {
		"name": "An ordered stack at the garage home's garage exit: every member reaches its slot",
		"description": "4 invaders ordered to stack (held) from every starting place each end in "
			+ "the slot they claimed, in time, without taking the back, aborting, walking the "
			+ "doorway's view or bumping (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	# Doors off until #159 makes this family door-aware.
	s.switch(&"worldgen.doors", false)
	s.house(1, "garage_home")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(650, -820), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", WRONG_START, { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Vector2(620, -560), { "max_health": 1_000_000.0 })
	s.actor(&"far_end", &"invader", Vector2(-70, -160), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(490, -760), "garage"), &"lead", -1, STARTS)
