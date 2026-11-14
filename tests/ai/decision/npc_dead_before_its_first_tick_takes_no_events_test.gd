extends GameTest
## An NPC killed before its controller has ever run (a body dead before its first tick) stops
## listening to the match like any dead NPC: its controller binds to the body's `died` when it is
## built, not on its first tick (a dead body never reaches it), so the shots and callouts of the
## rest of the match do not pile up in a queue nothing reads (`dead_npc_takes_no_events` is the NPC
## that died after its first tick).

const AT := Vector2(300, 200)
## Events posted after the death.
const EVENTS := 30


func describe() -> Dictionary:
	return {
		"name": "An NPC dead before its first tick queues no events",
		"description": "An invader killed before its controller ever ran adds nothing to the "
			+ "controller's event queue when shots and callouts are posted beside it.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"npc", &"invader", AT, { "movement:speed": 0.0, "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"debug_state")
	if not t.require(brain.get("_character") == null, "set-up: the controller never ran"):
		return
	npc.take_damage(1_000_000.0)
	for i in EVENTS:
		EventBus.post(
			&"hit",
			{
				"position": AT + Vector2(20, 0), "direction": Vector2.LEFT, "damage": 5.0,
				"attacker": null, "victim": null,
			},
		)
		EventBus.post(&"callout", { "position": AT + Vector2(40, 0), "kind": &"contact" })
	await t.frames(3)
	t.require(npc.is_dead, "premise: the invader is dead")
	t.expect_eq(
		(brain.get("_comms").event_queue as Array).size(),
		0,
		"no event of the match waits in the queue of an NPC that died before its first tick",
	)
