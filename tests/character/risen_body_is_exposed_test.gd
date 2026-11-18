extends GameTest
## P6 (docs/cover-and-stance.md): while a ducked shooter is risen over its cover its twin, its hit
## zones and its muzzle are the risen pose's: its head and shoulders show over the sofa and a body
## beyond the sofa hits them; ducked, the sofa hides it. A level ray at 45 px (over the sofa's 38,
## under the fire-over head top of 52) strikes the risen body and passes over the ducked one.

const SOFA_AT := Vector2(400, 250)
const HIDER_AT := Vector2(350, 250)
const SNIPER_AT := Vector2(700, 250)
const RISE_TIME := 0.2
const DWELL := 0.5
const HEAD_RAY := 45.0
const HEAD_AIM := 48.0


func describe() -> Dictionary:
	return {
		"name": "A risen shooter is hittable over its cover, a ducked one is not",
		"description": "A ducked body behind a sofa takes none of the rounds of a body across "
			+ "the sofa, until it rises to fire over it: then its head and shoulders take "
			+ "them, and a level ray at 45 px strikes its twin.",
		"tags": ["character", "posture", "crouch", "rise", "cover", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
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
	s.actor(&"hider", &"puppet", HIDER_AT, { "start_slot": 3, "max_health": 100_000.0 })
	s.actor(&"sniper", &"puppet", SNIPER_AT, { "start_slot": 3, "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var hider := t.actor(&"hider")
	t.require(hider.movement.set_posture(&"crouch"), "premise: the hider ducks")
	t.puppet(&"hider").aim_at(t.actor(&"sniper"))
	t.puppet(&"sniper").aim_at(hider)
	await t.seconds(0.6)
	t.check(not _twin_hit(t, HEAD_RAY), "ducked: a level ray at 45 px passes over its twin")
	# Ducked and silent, it takes nothing from a body shooting at it across the sofa.
	t.puppet(&"sniper").hold_fire(true)
	await t.seconds(0.3)
	t.check(_hits(t, t.object(&"sofa")) > 0, "the sniper's rounds meet the sofa")
	t.expect_eq(_hits(t, hider), 0, "and the ducked body is not struck")
	# (A pistol's magazine is twelve rounds: the sniper fires three here and under six below.)
	# It fires back: risen, its head and shoulders are over the sofa.
	t.puppet(&"hider").hold_fire(true)
	await t.seconds(RISE_TIME + 0.2)
	t.expect_eq(hider.movement.body_posture(), BodyHeights.FIRE_OVER, "premise: it has risen")
	# Aimed at the head that shows over the sofa (a torso shot at 33 px still meets the back).
	t.puppet(&"sniper").aim_at(hider, HEAD_AIM)
	t.check(_twin_hit(t, HEAD_RAY), "risen: a level ray at 45 px strikes its twin")
	await t.seconds(0.6)
	var struck := _hits(t, hider)
	t.check(struck > 0, "the risen body is struck over the sofa (%d)" % struck)
	t.check(
		hider._hit_zone(HEAD_RAY) == &"head" and hider._hit_zone(20.0) == &"legs",
		"its zones are the risen pose's: 45 px is the head, 20 px the legs",
	)
	t.puppet(&"hider").hold_fire(false)
	t.puppet(&"sniper").hold_fire(false)
	await t.seconds(DWELL + 0.3)
	t.expect_eq(hider.movement.body_posture(), BodyHeights.DUCK, "it drops back to the duck")
	t.check(not _twin_hit(t, HEAD_RAY), "and its twin is under the ray again")


## Whether the level ray at `height` px across the hider (north to south) strikes a character's
## twin.
func _twin_hit(t: TestContext, height: float) -> bool:
	var from := HIDER_AT - Vector2(0, 80)
	var to := HIDER_AT + Vector2(0, 80)
	var hit: Dictionary = t.world.twin_space().space().intersect_ray(
		PhysicsRayQueryParameters3D.create(
			PlanSpace.lift(from, height), PlanSpace.lift(to, height), PhysicsLayers.TWIN_CHARACTER
		)
	)
	return not hit.is_empty()


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
