extends GameTest
## H2 and P1 (docs/cover-and-stance.md): cover shelters a body by being taller than the line to it.
## An NPC aims at the middle of the part of its target it sees. A standing body behind a sofa (back
## 38 px) shows its head, chest and hips and is aimed at 53 px up from a 65 px muzzle: the line
## clears the back and strikes it. A ducked one (head top 36) behind the same sofa shows nothing
## of itself (the back is on its side, next to it): it is aimed at the torso, about 24 px up, and
## the back stops the round, the sofa is struck and the body is not. (With the back on the shooter's
## side the ducked head is seen over it and aimed at.)

const LANES := { &"stand": 150.0, &"crouch": 350.0 }
const SHOOT_X := 120.0
const SOFA_X := 400.0
## The target stands just behind the sofa (its back is on the body's side, east: it faces west).
const BODY_X := 447.0
const SOFA_BACK := 38.0


func describe() -> Dictionary:
	return {
		"name": "A standing body is hit over a sofa's back, a ducked one is not",
		"description": "A pistol round aimed at the torso of a body just behind a sofa: the "
			+ "standing one is struck over the back (38 px); the ducked one is hidden, the sofa "
			+ "takes the round.",
		"tags": ["projectile", "cover", "posture", "crouch", "ballistics"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	for lane: StringName in LANES:
		var y: float = LANES[lane]
		s.actor(StringName("shooter_%s" % lane), &"puppet", Vector2(SHOOT_X, y),
				{ "start_slot": 3 })
		s.object(
			StringName("sofa_%s" % lane),
			sofa,
			Vector2(SOFA_X, y),
			{ "facing": Vector2.LEFT },
		)
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, y),
				{ "max_health": 1_000_000.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	t.expect_near(
		PieceHeights.top_of(WorldGen.object_definition("sofa")), SOFA_BACK, 0.5,
		"premise: a sofa's back is 38 px",
	)
	t.check(t.actor(&"body_crouch").movement.set_posture(&"crouch"), "the body takes a crouch")
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).aim_at(t.actor(StringName("body_%s" % lane)))
	await t.seconds(0.5)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).shoot()
	await t.seconds(1.0)

	t.expect_eq(_hits(t, t.object(&"sofa_stand")), 0, "the round clears the back of the sofa")
	t.expect_eq(_hits(t, t.actor(&"body_stand")), 1, "and strikes the standing body behind it")
	t.expect_eq(_hits(t, t.object(&"sofa_crouch")), 1, "the ducked body's round meets the sofa")
	t.expect_eq(_hits(t, t.actor(&"body_crouch")), 0, "and the ducked body is not struck")


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
