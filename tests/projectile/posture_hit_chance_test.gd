extends GameTest
## P1 (docs/cover-and-stance.md): in the open a lower posture is a smaller target. A level round
## strikes a body when it flies under the body's head top, so at a pinned height each posture is
## struck or missed by the numbers alone (standing 74 px, ducked 36), and over a sweep of heights
## the hits follow the postures' heights: standing most, then ducked.

const LANES := { &"stand": 200.0, &"crouch": 400.0 }
const TARGET_X := 560.0
const SHOOT_X := 150.0


func describe() -> Dictionary:
	return {
		"name": "A lower posture is hit by fewer shots",
		"description": "Level rounds at pinned heights strike the postures they are under (10 and "
			+ "30: both, 50: standing, 90: none); a sweep of heights hits standing most, ducked "
			+ "less.",
		"tags": ["projectile", "posture", "crouch", "ballistics"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	for lane: StringName in LANES:
		s.actor(
			StringName("body_%s" % lane),
			&"puppet",
			Vector2(TARGET_X, LANES[lane]),
			{ "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		t.check(
			t.actor(StringName("body_%s" % lane)).movement.set_posture(lane),
			"the %s body takes its posture" % lane,
		)
	await t.frames(3)

	await _volley(t, [10.0])
	for lane: StringName in LANES:
		t.expect_eq(_hits(t, lane), 1, "a round at 10 strikes the %s body" % lane)
	await _volley(t, [30.0])
	t.expect_eq(_hits(t, &"stand"), 2, "a round at 30 strikes the standing body")
	t.expect_eq(_hits(t, &"crouch"), 2, "...and the ducked one (head top 36)")
	await _volley(t, [50.0])
	t.expect_eq(_hits(t, &"stand"), 3, "a round at 50 strikes only the standing body")
	t.expect_eq(_hits(t, &"crouch"), 2, "...over the ducked one")
	await _volley(t, [90.0])
	t.expect_eq(_hits(t, &"stand"), 3, "a round at 90 misses everyone")
	t.expect_eq(_hits(t, &"crouch"), 2, "...including the ducked")

	var before := {}
	for lane: StringName in LANES:
		before[lane] = _hits(t, lane)
	var sweep: Array = []
	for height in range(1, 101):
		sweep.append(float(height))
	await _volley(t, sweep)
	var struck := {}
	for lane: StringName in LANES:
		struck[lane] = _hits(t, lane) - before[lane]
		var posture := BodyHeights.DUCK if lane == &"crouch" else BodyHeights.STAND
		var want := BodyHeights.head_top(posture)
		t.expect_near(
			struck[lane], want, 2.0,
			"a %s body is struck by the rounds under its %.0f px (%d of 100)"
				% [lane, want, struck[lane]],
		)
	t.check(struck[&"stand"] > struck[&"crouch"], "standing is hit more than ducked")


## Fire a level round at each of `heights` down every lane and let them land.
func _volley(t: TestContext, heights: Array) -> void:
	for lane: StringName in LANES:
		for height: float in heights:
			var shot := Shot.new()
			shot.height = height
			ProjectileSpawner.spawn(Vector2(SHOOT_X, LANES[lane]), Vector2.RIGHT, t.world, shot)
	await t.seconds(0.6)


func _hits(t: TestContext, lane: StringName) -> int:
	var victim := t.actor(StringName("body_%s" % lane))
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
