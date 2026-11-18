extends GameTest
## P6 (docs/cover-and-stance.md): a ducked gun rises only for a round it could fire. An empty gun,
## and one still cycling between rounds, neither rise nor renew the rise (a click on one does not
## stand the body up in view for nothing). And a slow gun's rise outlasts its time between rounds
## (the dwell is at least the interval plus `dwell_margin`): it stays risen between its rounds
## rather than ducking and rising again for each.

const EMPTY_SHOOTER := Vector2(350, 150)
const SLOW_SHOOTER := Vector2(350, 350)
const SOFA_X := 400.0
const TARGET_X := 700.0
const RISE_TIME := 0.1
const DWELL := 0.3
## A bolt-action's time between rounds, longer than the dwell.
const SLOW := 1.0


func describe() -> Dictionary:
	return {
		"name": "A gun that cannot fire does not rise; a slow gun stays risen between rounds",
		"description": "Behind a sofa an empty pistol never rises; a slow pistol rises, fires, "
			+ "stays risen through its cooldown to fire again, and once ducked while it cools it "
			+ "does not rise until it can fire.",
		"tags": ["character", "posture", "crouch", "rise", "ammo", "cover"],
		"timeout": 20.0,
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
		straight[gun]["fire_interval"] = SLOW
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	for lane: Vector2 in [EMPTY_SHOOTER, SLOW_SHOOTER]:
		var key := StringName("sofa_%d" % int(lane.y))
		s.object(key, sofa, Vector2(SOFA_X, lane.y), { "facing": Vector2.RIGHT })
		s.actor(StringName("target_%d" % int(lane.y)), &"puppet", Vector2(TARGET_X, lane.y), {
			"max_health": 100_000.0,
		})
	s.actor(
		&"empty",
		&"puppet",
		EMPTY_SHOOTER,
		{ "start_slot": 3, "max_health": 100_000.0, "inventory:start_rounds": 0 },
	)
	s.actor(&"slow", &"puppet", SLOW_SHOOTER, { "start_slot": 3, "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	for who: StringName in [&"empty", &"slow"]:
		t.require(t.actor(who).movement.set_posture(&"crouch"), "premise: %s ducks" % who)
		var lane := int(t.actor(who).global_position.y)
		t.puppet(who).aim_at(t.actor(StringName("target_%d" % lane)))
	await t.seconds(0.5)
	t.expect_eq(
		t.actor(&"empty").inventory.current_item().ammo.rounds_loaded(),
		0,
		"premise: empty",
	)
	t.puppet(&"empty").hold_fire(true)
	t.puppet(&"slow").hold_fire(true)
	await t.seconds(0.6)
	var empty := t.actor(&"empty")
	t.expect_eq(empty.movement.body_posture(), BodyHeights.DUCK, "the empty gun does not rise")
	t.check(not empty.weapon.rise.rising(), "and is not rising")
	t.expect_eq(_rounds(t, &"empty"), 0, "and fires nothing")

	var slow := t.actor(&"slow")
	t.expect_eq(_rounds(t, &"slow"), 1, "the slow gun fired its first round")
	t.expect_eq(slow.movement.body_posture(), BodyHeights.FIRE_OVER, "risen to fire it")
	await t.seconds(SLOW - 0.4)
	t.expect_eq(
		slow.movement.body_posture(),
		BodyHeights.FIRE_OVER,
		"it stays risen through the cooldown, past the dwell",
	)
	var second := await t.until(func(): return _rounds(t, &"slow") == 2, 2.0)
	t.check(second, "and fires its next round when it is due, still risen")

	# Ducked mid-cooldown, it does not rise for a round it cannot fire.
	slow.weapon.rise.drop()
	await t.seconds(0.5)
	t.expect_eq(slow.movement.body_posture(), BodyHeights.DUCK, "cooling, it does not rise")
	t.check(not slow.weapon.rise.rising(), "and is not rising")
	t.expect_eq(_rounds(t, &"slow"), 2, "and fires nothing meanwhile")
	var fired := await t.until(func(): return _rounds(t, &"slow") == 3, 3.0)
	t.check(fired, "once the cooldown is over it rises and fires")
	t.expect_eq(slow.movement.body_posture(), BodyHeights.FIRE_OVER, "risen to fire it")


func _rounds(t: TestContext, who: StringName) -> int:
	return t.events_of(&"shot", func(d): return d["attacker"] == t.actor(who)).size()
