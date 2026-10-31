extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 (the stack moves up): a move-up waits for a
## latecomer near the slot it would take only when the latecomer's way there runs through the
## mover's step (`stack_move_up_waits_for_near_latecomer`); one coming up behind the mover, on the
## same lane, follows it in. The pocket kitchen (`tests/_ai/pocket_kitchen_probe.gd`: a garage
## home's kitchen at its 52 px doorway into the garage), four members ordered to stack on the
## doorway on its east side, starting where the garage home's tests start them, all at walking
## pace: `near` and `wrong` by the door, `far` in the kitchen's far corner and `beyond` in the
## garage. The scenario is a move-up whose latecomer comes up its lane close behind the mover,
## within `MOVE_UP_REACH` + `MOVE_UP_MARGIN` of the slot the move-up frees: the run requires one
## (`Reach.run_with_move_up`), the mover must move up and the follower follow it into the slot it
## frees. Each member must end in the slot it claimed, in time, never take the back of
## the stack or abort, keep out of the doorway's view, and never bump a teammate
## (`tests/_ai/reach_probe.gd`).

const Reach := preload("res://tests/_ai/reach_probe.gd")
const Pocket := preload("res://tests/_ai/pocket_kitchen_probe.gd")
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"far": "in the same room, far from the door (the kitchen's far corner)",
		&"beyond": "in the room beyond (the garage)",
}


func describe() -> Dictionary:
	return {
		"name": "A move-up lets the follower in",
		"description": "4 invaders ordered to stack (held) at the pocket kitchen's door to "
			+ "the garage: slot 2's holder comes up its lane close behind the member in slot 4, "
			+ "which moves up into slot 2 and lets it in; every member ends in the slot it "
			+ "claimed, in time, never taking the back or aborting (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	Pocket.layout(s)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Pocket.NEAR, { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Pocket.WRONG, { "max_health": 1_000_000.0 })
	s.actor(&"far", &"invader", Pocket.FAR, { "max_health": 1_000_000.0 })
	s.actor(&"beyond", &"invader", Pocket.BEYOND, { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run_with_move_up(t, Reach.frame(t, Pocket.DOOR, "garage"), &"lead", 1, STARTS)
