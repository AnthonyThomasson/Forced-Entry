extends GameTest
## Rule 9 and the move-up (ticket #65 round 2, `docs/tactical-entry.md` E2): a regression guard that
## the move-up leaves the latecomer a way into the slot it frees (it guards the move-up rule as it
## is; there is no rule against a move-up that would seal a slot). The pocket kitchen
## (`tests/_ai/pocket_kitchen_probe.gd`: a garage home's kitchen at its 52 px doorway into the
## garage), four members ordered to stack on the doorway on its east side: `near` and `wrong` start
## by the door where the garage home's tests start them, `far` east of the island and `beyond` at
## the garage's far end. `far` walks slowly (`FAR_SPEED`), so a member in a high slot stands in its
## slot long before the holder of the slot below it is there, and moves up (the run requires one,
## `Reach.run_with_move_up`). Whatever moves up, each member must end in the slot it claimed, in
## time, never take the back of the stack or abort, keep out of the doorway's view, and never bump a
## teammate (`tests/_ai/reach_probe.gd`).

const Reach := preload("res://tests/_ai/reach_probe.gd")
const Pocket := preload("res://tests/_ai/pocket_kitchen_probe.gd")
## `far`'s speed (px/s; a walk is 150): it reaches the stack after `beyond` stands in its slot.
const FAR_SPEED := 60.0
## Where `far` starts (east of the island) and `beyond` (the garage's far end).
const FAR_AT := Vector2(610, -120)
const BEYOND_AT := Vector2(380, -700)
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"far": "in the same room, east of the island, walking slowly",
		&"beyond": "in the room beyond (the garage), at its far end",
}


func describe() -> Dictionary:
	return {
		"name": "A move-up never leaves the freed slot out of the latecomer's reach",
		"description": "4 invaders ordered to stack (held) at the pocket kitchen's door to "
			+ "the garage, slot 3's holder coming in slowly long after slot 4's stands in its "
			+ "slot: whatever moves up, every member ends in the slot it claimed, in time, never "
			+ "taking the back or aborting (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	Pocket.layout(s)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Pocket.NEAR, { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Pocket.WRONG, { "max_health": 1_000_000.0 })
	s.actor(
		&"far",
		&"invader",
		FAR_AT,
		{ "max_health": 1_000_000.0, "movement:speed": FAR_SPEED },
	)
	s.actor(&"beyond", &"invader", BEYOND_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run_with_move_up(t, Reach.frame(t, Pocket.DOOR, "garage"), &"lead", 1, STARTS)
