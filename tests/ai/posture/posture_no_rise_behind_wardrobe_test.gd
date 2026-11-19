extends GameTest
## A defender fighting from behind cover fires by rising over it (docs/cover-and-stance.md A1, P6).
## A crouched defender with a hostile in view behind a wardrobe, which no pose clears (90 px): it
## does not rise, and its rounds meet the wardrobe. Server down.

const COVER_AT := Vector2(340, 150)
const DEFENDER_AT := Vector2(300, 150)
const FOE_AT := Vector2(750, 150)


func describe() -> Dictionary:
	return {
		"name": "A defender behind a wardrobe does not rise",
		"description": "Fighting from behind a wardrobe with the server down: the defender "
			+ "crouches and fires but stays ducked; its rounds meet the wardrobe.",
		"tags": ["ai", "posture", "crouch", "cover", "rise"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 300))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	s.actor(&"defender", &"defender", DEFENDER_AT)
	s.actor(&"foe", &"puppet", FOE_AT, { "faction": &"invader", "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var defender: Node = t.actor(&"defender")
	defender.movement.aim_point = FOE_AT
	# The defender sees the hostile first, then the wardrobe is set down in front of it, close
	# enough that the defender is standing against it (a piece placed where a body stands is moved
	# clear at once by the physics), and the hostile is known and out of sight behind it.
	var seen := func() -> bool:
		var state: Dictionary = t.controller(&"defender", &"debug_state").debug_state()
		return (state.get("contacts", []) as Array).any(
			func(c): return c.get("hostile", false) and c.get("visible", false)
		)
	if not t.require(await t.until(seen, 5.0), "premise: the defender sees the hostile"):
		return
	var wardrobe := ObjectFactory.spawn(
		WorldGen.object_definition("wardrobe"), COVER_AT, t.world, { "facing": Vector2.RIGHT }
	)
	t.check(
		await t.until(func(): return _rounds(t, defender) > 0, 20.0),
		"the defender behind the wardrobe fires",
	)
	await t.seconds(2.0)
	t.expect_eq(defender.movement.posture(), &"crouch", "it fights crouched")
	t.expect_eq(defender.movement.body_posture(), BodyHeights.DUCK, "and does not rise")
	t.check(_hits(t, wardrobe) > 0, "its rounds meet the wardrobe")
	t.expect_eq(_hits(t, t.actor(&"foe")), 0, "and none reaches the hostile")


func _rounds(t: TestContext, who: Node) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == who).size()


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
