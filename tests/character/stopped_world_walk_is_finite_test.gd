extends GameTest
## A world stopped (`Engine.time_scale` 0) still runs physics frames, with a step of no length: the
## character's twin then reports no motion, not the 0/0 of its body's real velocity, so the pose,
## the rig and the legs' casts stay finite (#194: a NaN pose never recovers, and each NaN cast is
## enormously slow). Run again, the body walks on.


func describe() -> Dictionary:
	return {
		"name": "A step of no length moves a character at zero, finite velocity",
		"description": "A walking body in a stopped world reports a zero velocity and keeps a "
			+ "finite pose; the world run again, it walks on.",
		"tags": ["twin", "pose", "legs"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 300))
	s.switch(&"nav.rebake", false)
	s.actor(&"walker", &"puppet", Vector2(150, 150))


func run(t: TestContext) -> void:
	var body: Node2D = t.actor(&"walker")
	t.puppet(&"walker").walk_to(Vector2(800, 150))
	await t.seconds(0.5)
	t.require(TwinSpace.real_velocity_of(body).length() > 10.0, "premise: it walks")
	Engine.time_scale = 0.0
	for i in 3:
		await t.world.get_tree().physics_frame
	await t.world.get_tree().process_frame
	var stopped := TwinSpace.real_velocity_of(body)
	var walk: float = body.anatomy.pose.gait.walk_amount()
	var ankle: Vector3 = body.anatomy.rig().point(14)
	var delta := body.get_physics_process_delta_time()
	Engine.time_scale = 1.0
	t.require(delta == 0.0, "premise: the steps had no length (%f)" % delta)
	t.check(stopped == Vector2.ZERO, "a step of no length moves it at zero (%s)" % stopped)
	t.check(is_finite(walk), "its gait stays finite (%f)" % walk)
	t.check(ankle.is_finite(), "its rig stays finite (%s)" % ankle)
	await t.seconds(0.3)
	t.check(TwinSpace.real_velocity_of(body).length() > 10.0, "run again, it walks on")
