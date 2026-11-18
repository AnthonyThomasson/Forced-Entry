extends GameTest
## P6 (docs/cover-and-stance.md): a ducked shooter that fires behind cover its duck muzzle cannot
## clear rises to the lowest pose that does. Behind a sofa (back 38 px, over the duck's 30 px bore
## and under the fire-over's 43) it rises to FIRE_OVER after `CharacterRiseConfig.rise_time`, fires
## over the back and hits a standing target beyond it, and drops back to the duck once the trigger
## has been up for the dwell (the twin and the zones follow the pose).

const SOFA_AT := Vector2(400, 250)
## 25 px short of the sofa's back (its west face at x 375).
const SHOOTER_AT := Vector2(350, 250)
const TARGET_AT := Vector2(700, 250)
const RISE_TIME := 0.3
const DWELL := 0.5


func describe() -> Dictionary:
	return {
		"name": "A ducked shooter behind a sofa rises to fire over it, then drops",
		"description": "A crouched pistol shooter (trigger held) just short of a sofa's back "
			+ "fires at a body beyond it: it rises to the fire-over pose, fires after the rise "
			+ "time, hits the body and not the sofa, and is ducked again a dwell after it lets "
			+ "go.",
		"tags": ["character", "posture", "crouch", "rise", "cover", "ballistics"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(CharacterRiseConfig, &"rise_time", RISE_TIME)
	s.set_static(CharacterRiseConfig, &"dwell", DWELL)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
		straight[gun]["automatic"] = true
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	s.object(&"sofa", sofa, SOFA_AT, { "facing": Vector2.RIGHT })
	s.actor(&"shooter", &"puppet", SHOOTER_AT, { "start_slot": 3, "max_health": 100_000.0 })
	s.actor(&"target", &"puppet", TARGET_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var shooter := t.actor(&"shooter")
	var puppet := t.puppet(&"shooter")
	t.require(shooter.movement.set_posture(&"crouch"), "premise: the shooter ducks")
	puppet.aim_at(t.actor(&"target"))
	await t.seconds(0.6)
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.DUCK, "premise: ducked until it fires")
	t.check(
		BodyHeights.lowest_clearing(PieceHeights.top_of(WorldGen.object_definition("sofa")))
			== BodyHeights.FIRE_OVER,
		"premise: a sofa's back wants the fire-over pose",
	)
	puppet.hold_fire(true)
	await t.frames(3)
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.FIRE_OVER, "it rises to fire over")
	t.expect_eq(_rounds(t), 0, "and holds its fire while it rises")
	await t.seconds(RISE_TIME + 0.4)
	t.check(_rounds(t) > 0, "then fires")
	t.expect_eq(
		shooter.movement.body_posture(),
		BodyHeights.FIRE_OVER,
		"it stays risen while firing",
	)
	puppet.hold_fire(false)
	await t.seconds(0.4)
	t.check(_hits(t, t.actor(&"target")) > 0, "the rounds hit the body beyond the sofa")
	t.expect_eq(_hits(t, t.object(&"sofa")), 0, "and none strikes the sofa")
	t.expect_eq(
		shooter.movement.body_posture(),
		BodyHeights.FIRE_OVER,
		"it holds the rise for the dwell",
	)
	await t.seconds(DWELL)
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.DUCK, "then drops back to the duck")
	t.expect_eq(shooter.movement.posture(), &"crouch", "still crouching")


func _rounds(t: TestContext) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == t.actor(&"shooter")).size()


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
