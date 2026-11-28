extends GameTest
## P6 (docs/cover-and-stance.md): a rise ends when the body does what ends it. Standing up (and
## crouching again) drops it, with no stale rise left to come back; a reload under way does not hold
## it (nothing fires, so the dwell runs out and the body ducks) and the body rises again for the
## first round after the reload; a death mid-rise drops it (nothing of the rise is left on a
## corpse).

const SOFA_AT := Vector2(400, 250)
const SHOOTER_AT := Vector2(350, 250)
const TARGET_AT := Vector2(700, 250)
const RISE_TIME := 0.1
const DWELL := 0.3


func describe() -> Dictionary:
	return {
		"name": "A rise is dropped by standing up and by death, and a reload does not hold it",
		"description": "A ducked pistol shooter behind a sofa, risen: standing up drops the "
			+ "rise (and a new crouch is the duck); a reload lets it duck and it rises again for "
			+ "the next round; a death clears it.",
		"tags": ["character", "posture", "crouch", "rise", "ammo", "death"],
		"timeout": 25.0,
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
	s.actor(&"shooter", &"puppet", SHOOTER_AT, { "start_slot": 3, "max_health": 50.0 })
	s.actor(&"target", &"puppet", TARGET_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var shooter := t.actor(&"shooter")
	var puppet := t.puppet(&"shooter")
	t.require(shooter.movement.set_posture(&"crouch"), "premise: the shooter ducks")
	puppet.aim_at(t.actor(&"target"))
	await t.seconds(0.5)

	# Stand up mid-dwell.
	puppet.hold_fire(true)
	await t.seconds(RISE_TIME + 0.2)
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.FIRE_OVER, "premise: risen")
	puppet.hold_fire(false)
	t.require(shooter.movement.set_posture(&"stand"), "it stands up")
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.STAND, "standing")
	t.expect_eq(shooter.weapon.rise.pose(), BodyHeights.NONE, "no rise is left")
	t.require(shooter.movement.set_posture(&"crouch"), "it crouches again")
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.DUCK, "the new crouch is the duck")
	t.check(not shooter.weapon.rise.rising(), "and nothing is rising")
	await t.seconds(0.3)

	# A reload does not hold the rise.
	puppet.hold_fire(true)
	await t.until(func(): return _rounds(t) >= 2, 3.0)
	puppet.reload()
	await t.frames(2)
	t.require(shooter.ammo.is_reloading(), "premise: it is reloading")
	var before := _rounds(t)
	await t.seconds(DWELL + 0.4)
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.DUCK, "reloading, it ducks again")
	t.expect_eq(_rounds(t), before, "and fires nothing meanwhile")
	var again := await t.until(func(): return _rounds(t) > before, 5.0)
	t.check(again, "after the reload it fires again")
	t.expect_eq(shooter.movement.body_posture(), BodyHeights.FIRE_OVER, "having risen for it")

	# Death mid-dwell.
	shooter.take_damage(1000.0)
	t.check(shooter.is_dead, "premise: it dies")
	t.expect_eq(shooter.weapon.rise.pose(), BodyHeights.NONE, "nothing of the rise is left")
	t.check(not shooter.weapon.rise.rising(), "and nothing is rising")


func _rounds(t: TestContext) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == t.actor(&"shooter")).size()
