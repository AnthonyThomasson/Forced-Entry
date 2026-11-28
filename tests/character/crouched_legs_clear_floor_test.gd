extends GameTest
## A crouched character's feet are swept above the floor (#194): at the duck's ankle
## height a foot-sized sphere would reach below the floor slab and be stopped by it, so a crouched
## walker in the open would have both feet collapsed on its centre.

const Probe := preload("res://tests/_general/twin_probe.gd")
const REACH := Vector2(12.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "A crouched character's feet are not stopped by the floor",
		"description": "In an open arena a foot swept the length of a stride at the crouched ankle "
			+ "height goes all the way, as it does standing.",
		"tags": ["character", "3d", "heights", "posture", "legs"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 500))
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"puppet", &"puppet", Vector2(300, 250))


func run(t: TestContext) -> void:
	await t.frames(3)
	var body := t.actor(&"puppet")
	var sweep = body.anatomy.sweep
	var slab: float = Probe.top_at(t, body.global_position + REACH, PhysicsLayers.TWIN_WORLD)
	var foot: float = BodyHeights.contact(&"ankle", BodyHeights.DUCK)
	t.require(slab > 0.0, "premise: a floor slab is in the sweep's world (top %.2f px)" % slab)
	t.require(
		foot - CharacterPushConfig.leg_radius < slab,
		"premise: the crouched foot's sphere reaches below the slab's top (%.2f)"
			% (foot - CharacterPushConfig.leg_radius),
	)
	var stood: Vector2 = sweep.circle(
		body.global_position, REACH, CharacterPushConfig.leg_radius,
		BodyHeights.contact(&"ankle", BodyHeights.STAND))
	t.expect_near(stood.x, REACH.x, 0.01, "standing, a foot sweeps the whole stride")
	t.require(body.movement.set_posture(&"crouch"), "premise: it can crouch")
	await t.frames(3)
	var crouched: Vector2 = sweep.circle(
		body.global_position, REACH, CharacterPushConfig.leg_radius,
		BodyHeights.contact(&"ankle", body.movement.body_posture()))
	t.expect_near(crouched.x, REACH.x, 0.01, "crouched, it sweeps the whole stride too")
