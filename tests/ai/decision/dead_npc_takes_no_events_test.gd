extends GameTest
## A dead NPC's controller no longer listens to the match's events: its body never calls it again,
## so nothing would ever read what it queued, and every shot and callout of the rest of the match
## would pile up in its queue. The controller stops listening on the character's `died` and empties
## what it had. One invader is killed, then the match goes on around its corpse: shots land and
## callouts are radioed beside it.

const AT := Vector2(300, 200)
## Events posted after the death.
const EVENTS := 30


func describe() -> Dictionary:
	return {
		"name": "A dead NPC queues no more events",
		"description": "After an invader is killed, shots and callouts posted beside it add "
			+ "nothing to its controller's event queue and force no decision.",
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
	await t.frames(3)
	npc.take_damage(1_000_000.0)
	await t.frames(2)
	if not t.require(npc.is_dead, "set-up: the invader is dead"):
		return
	var queue: Array = brain.get("_comms").event_queue
	var forced_before: bool = brain.get("_cadence").forced
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
	t.expect_eq(queue.size(), 0, "no event of the match after its death waits in the queue")
	t.expect_eq(
		bool(brain.get("_cadence").forced), forced_before, "and none forces a decision on it"
	)
