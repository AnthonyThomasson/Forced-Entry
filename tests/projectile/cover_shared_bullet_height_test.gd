extends GameTest
## H1, H2 (docs/cover-and-stance.md): a round flies one line, so cover shelters what is lower than
## it. A sofa (back 38 px) stands before a standing body (head top 74) and before a ducked one (head
## top 36). Rounds level at a pinned height: those under 38 strike the sofa, which stops them before
## either body; those between 38 and 74 clear it and strike only the standing body, and fly over the
## ducked one (36 is under the sofa's back: nothing that clears the sofa reaches it); those over 74
## clear everything.

const LANES := { &"stand": 150.0, &"crouch": 350.0 }
const SHOOT_X := 120.0
const SOFA_X := 400.0
## The body stands just behind the sofa (its back is the near side: it faces east).
const BODY_X := 447.0
## Round heights (px) and what each meets: the sofa (under 38), the standing body (38 to 74) or
## nothing.
const LOW := [10.0, 20.0, 30.0, 37.0]
const MID := [40.0, 55.0, 70.0]
const HIGH := [80.0, 95.0]


func describe() -> Dictionary:
	return {
		"name": "A round's line meets cover and the body behind it by height",
		"description": "Level rounds at pinned heights strike a sofa (38 px) when lower, only the "
			+ "standing body behind it (74) when between, never the ducked one (36) behind it, "
			+ "and nothing when higher.",
		"tags": ["projectile", "cover", "posture", "ballistics"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	sofa["anchored"] = true
	for lane: StringName in LANES:
		s.object(StringName("cover_%s" % lane), sofa, Vector2(SOFA_X, LANES[lane]),
				{ "facing": Vector2.RIGHT })
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, LANES[lane]),
				{ "max_health": 1_000_000.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	t.check(t.actor(&"body_crouch").movement.set_posture(&"crouch"), "the second body ducks")
	await t.frames(3)
	t.expect_near(
		BodyHeights.head_top(BodyHeights.DUCK), 36.0, 0.5, "premise: the duck's head top is 36",
	)
	t.expect_near(PieceHeights.top_of(WorldGen.object_definition("sofa")), 38.0, 0.5,
			"premise: the sofa's back is 38")

	await _volley(t, LOW)
	for lane: StringName in LANES:
		t.expect_eq(
			_hits(t, _cover(t, lane)),
			LOW.size(),
			"the low rounds strike the %s lane's sofa" % lane,
		)
		t.expect_eq(_hits(t, _body(t, lane)), 0, "...which stops them before the %s body" % lane)

	await _volley(t, MID)
	t.expect_eq(_hits(t, _cover(t, &"stand")), LOW.size(), "the middle rounds clear the sofa")
	t.expect_eq(_hits(t, _body(t, &"stand")), MID.size(), "...and strike the standing body")
	t.expect_eq(_hits(t, _cover(t, &"crouch")), LOW.size(), "...the other sofa too")
	t.expect_eq(_hits(t, _body(t, &"crouch")), 0, "...and pass over the ducked body behind it")

	await _volley(t, HIGH)
	t.expect_eq(_hits(t, _body(t, &"stand")), MID.size(), "the high rounds clear the standing body")
	t.expect_eq(_hits(t, _cover(t, &"stand")), LOW.size(), "...and the sofa")
	t.expect_eq(_hits(t, _body(t, &"crouch")), 0, "...and the ducked one")


## Fire a level round at each of `heights` down every lane and let them land.
func _volley(t: TestContext, heights: Array) -> void:
	for lane: StringName in LANES:
		for height: float in heights:
			var shot := Shot.new()
			shot.height = height
			ProjectileSpawner.spawn(Vector2(SHOOT_X, LANES[lane]), Vector2.RIGHT, t.world, shot)
	await t.seconds(0.6)


func _cover(t: TestContext, lane: StringName) -> Node:
	return t.object(StringName("cover_%s" % lane))


func _body(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("body_%s" % lane))


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
