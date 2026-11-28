extends GameTest
## What Von is told about postures: a hostile seen crouching is "crouched low" in its contact line,
## a hostile standing says nothing of the kind, and the defender's own state says "You are
## crouching." only once it has taken a crouch — a standing defender's text carries no posture words
## at all.


func describe() -> Dictionary:
	return {
		"name": "Von is told about postures only when someone is not standing",
		"description": "A defender pinned standing (the posture switch off) and a standing "
			+ "hostile leave posture words out of every ask's state; once the hostile crouches "
			+ "it is crouched low; the defender's own situation says 'You are crouching.' "
			+ "exactly when it is crouching as the snapshot is built.",
		"tags": ["ai", "posture", "decision", "scripted", "snapshot"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	# The defender never ducks (a decision builds its state some frames before the ask, and a
	# duck reflex between the two would make the state say what the ask cannot tell).
	s.switch(&"ai.posture", false)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"defender", &"defender", Vector2(200, 300), { "max_health": 400.0 })
	s.actor(
		&"stranger",
		&"puppet",
		Vector2(600, 300),
		{ "start_slot": 1, "faction": &"invader", "max_health": 400.0 },
	)


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	defender.movement.aim_point = t.actor(&"stranger").global_position
	t.check(
		await t.until(func(): return not DecisionStub.requests.is_empty(), 8.0),
		"the defender asked Von",
	)
	var first: String = String(DecisionStub.requests[0]["state"])
	t.check(first.contains("holding a"), "the state has the usual situation line")
	t.check(not first.contains("crouch"), "a standing defender's state has no posture words")
	t.expect_eq(defender.movement.posture(), &"stand", "the defender stayed standing")

	# The hostile crouches; later asks mention it, and still none speaks of the defender's own.
	var asked := DecisionStub.requests.size()
	t.puppet(&"stranger").set_posture(&"crouch")
	t.check(
		await t.until(
			func(): return DecisionStub.requests.slice(asked).any(
				func(r): return String(r["state"]).contains("crouched low")
			),
			15.0,
		),
		"a hostile seen crouching is crouched low",
	)
	t.check(
		DecisionStub.requests.all(func(r): return not String(r["state"]).contains("crouching")),
		"no ask of the standing defender says it is crouching",
	)

	# Pinned crouch: the situation is read as the snapshot is built, so a crouch taken and a
	# snapshot built in one frame say it, and a stand taken and built again do not.
	var brain := t.controller(&"defender", &"debug_state")
	var perception: Node = brain.get("_perception")
	var goal: String = brain.get("goal")
	defender.movement.set_posture(&"crouch")
	t.expect_eq(defender.movement.posture(), &"crouch", "set-up: the defender is crouching")
	var low: String = perception.sense(goal, "", 0)["sections"]["situation"]
	t.check(low.contains("You are crouching."), "a crouching defender's situation says so: " + low)
	defender.movement.set_posture(&"stand")
	var high: String = perception.sense(goal, "", 0)["sections"]["situation"]
	t.check(not high.contains("crouch"), "and standing again it does not: " + high)
