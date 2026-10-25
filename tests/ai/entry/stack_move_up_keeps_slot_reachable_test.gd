extends GameTest
## Rule 9 and the move-up (ticket #65 round 2, `docs/tactical-entry.md` E2): a regression guard that
## the move-up leaves the latecomer a way into the slot it frees (it guards the move-up rule as it
## is; there is no rule against a move-up that would seal a slot). The garage home (seed 1,
## furnished) doorway from the kitchen into the garage, the stack of `garage_six` on its east side,
## four members starting where `garage_six`'s do: `near` and `wrong` by the door, `far` in the
## kitchen's far corner and `beyond` in the garage. `far` walks slowly (`FAR_SPEED`), so `beyond`
## stands in its slot long before `far`, the holder of the slot below it, is there. Whatever moves
## up, each member must end in the slot it claimed, in time, never take the back of the stack or
## abort, keep out of the doorway's view, and never bump a teammate (`tests/_ai/reach_probe.gd`).

const Reach := preload("res://tests/_ai/reach_probe.gd")
## `far`'s speed (px/s; a walk is 150): it reaches the stack after `beyond` stands in its slot.
const FAR_SPEED := 60.0
## Where each member starts.
const STARTS := {
		&"near": "in the same room, near along the wall, on the order's side",
		&"wrong": "in the same room, on the wrong side of the door",
		&"far": "in the same room, far from the door (the kitchen's far corner), walking slowly",
		&"beyond": "in the room beyond (the garage)",
}


func describe() -> Dictionary:
	return {
		"name": "A move-up never leaves the freed slot out of the latecomer's reach",
		"description": "4 invaders ordered to stack (held) at the garage home's kitchen door to "
			+ "the garage, slot 3's holder coming in slowly long after slot 4's stands in its "
			+ "slot: whatever moves up, every member ends in the slot it claimed, in time, never "
			+ "taking the back or aborting (rule 9).",
		"tags": ["ai", "entry", "leadership", "order", "stack", "scripted"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "garage_home")
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"near", &"invader", Vector2(615, -295), { "max_health": 1_000_000.0 })
	s.actor(&"wrong", &"invader", Vector2(420, -300), { "max_health": 1_000_000.0 })
	s.actor(
		&"far",
		&"invader",
		Vector2(660, -30),
		{ "max_health": 1_000_000.0, "speed": FAR_SPEED },
	)
	s.actor(&"beyond", &"invader", Vector2(380, -470), { "max_health": 1_000_000.0 })
	s.actor(
		&"lead",
		&"puppet",
		Vector2(-900, 300),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	await Reach.run(t, Reach.frame(t, Vector2(500, -360), "garage"), &"lead", 1, STARTS)
