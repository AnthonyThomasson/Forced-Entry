extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 (the stack moves up): a move-up waits for a
## latecomer near the slot it would take only when the latecomer's way there runs through the
## mover's step (`stack_move_up_waits_for_near_latecomer`); one coming up behind the mover, on the
## same lane, follows it in. The garage home (seed 1, furnished) doorway from the kitchen into the
## garage, the stack of `garage_six` on its east side, four members starting where `garage_six`'s
## do, all at walking pace: `near` and `wrong` by the door, `far` in the kitchen's far corner and
## `beyond` in the garage. `far` reaches slot 3 first and `beyond` stands in slot 4; slot 2 lies
## straight behind slot 4 on `near`'s lane in from the south, `near` coming up it close behind
## `beyond` (within `MOVE_UP_REACH` + `MOVE_UP_MARGIN` of slot 4). With `beyond` standing in slot 4
## and `wrong` in slot 1 the way to slot 2 is closed, so `beyond` must move up into it and `near`
## follow into slot 4. Each member must end in the slot it claimed, in time, never take the back of
## the stack or abort, keep out of the doorway's view, and never bump a teammate
## (`tests/_ai/reach_probe.gd`).

const Reach := preload("res://tests/_ai/reach_probe.gd")
const IDS := [&"near", &"wrong", &"far", &"beyond"]
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
		"description": "4 invaders ordered to stack (held) at the garage home's kitchen door to "
			+ "the garage: slot 2's holder comes up its lane close behind the member in slot 4, "
			+ "which moves up into slot 2 and lets it in; every member ends in the slot it "
			+ "claimed, in time, never taking the back or aborting (rule 9).",
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
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(500, -360), "garage"), IDS, &"lead", 1, STARTS)
