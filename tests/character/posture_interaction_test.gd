extends GameTest
## Posture and interactions: sitting on a chair stands a crouched character up and locks the posture
## while seated; a dead character takes no posture; an unknown posture is refused.


func describe() -> Dictionary:
	return {
		"name": "Sitting stands the character up and locks the posture",
		"description": "interact_with from a crouch leaves the character standing, set_posture is "
			+ "refused while seated or dead, and a bad name is refused.",
		"tags": ["posture", "crouch", "interaction", "death"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 500, 400))
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"sitter", &"puppet", Vector2(220, 200))
	s.actor(&"victim", &"puppet", Vector2(220, 330))
	s.object(&"chair", "chair", Vector2(258, 200))


func run(t: TestContext) -> void:
	var sitter := t.actor(&"sitter")
	var p := t.puppet(&"sitter")
	t.check(not sitter.movement.set_posture(&"hover"), "an unknown posture is refused")
	t.check(sitter.movement.set_posture(&"crouch"), "crouches beside the chair")
	p.aim_at(t.object(&"chair"))
	await t.seconds(0.2)
	p.interact(t.object(&"chair"), "sit")
	if not t.require(await t.until(sitter.is_busy, 1.0), "sitting makes the character busy"):
		return
	t.expect_eq(sitter.movement.posture(), &"stand", "an interaction stands the character up")
	t.check(not sitter.movement.set_posture(&"crouch"), "no posture change while seated")
	t.expect_eq(sitter.movement.posture(), &"stand", "still standing")
	p.end_interaction()
	await t.until(func(): return not sitter.is_busy(), 1.0, "standing up frees the character")
	t.check(sitter.movement.set_posture(&"crouch"), "free again, it can crouch")

	# A dead character keeps no posture and takes none.
	var victim := t.actor(&"victim")
	t.check(victim.movement.set_posture(&"crouch"), "the victim crouches")
	victim.take_damage(victim.max_health)
	await t.frames(2)
	t.check(victim.is_dead, "the victim died")
	t.expect_eq(victim.movement.posture(), &"stand", "a body falls from the standing skeleton")
	t.check(not victim.movement.set_posture(&"crouch"), "a dead character takes no posture")
