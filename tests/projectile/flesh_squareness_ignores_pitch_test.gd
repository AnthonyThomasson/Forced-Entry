extends GameTest
## A body's wall is straight up, so how square a round meets a body is a matter of its floor-plan
## heading alone: a round coming down at a steep pitch onto the middle of a standing body's torso
## deals what a level one does there (squareness 1 head-on), not a cosine of the pitch less.

const BODY_X := 500.0
const LANES := { &"level": [150.0, 50.0, 0.0, 30.0], &"pitched": [350.0, 70.0, -0.4, 80.0] }


func describe() -> Dictionary:
	return {
		"name": "A pitched round deals a body what a level one does",
		"description": "Pistol rounds at a standing body's torso, one level and one falling at a "
			+ "steep pitch, both head-on in plan: the same health lost.",
		"tags": ["projectile", "squareness", "ballistics", "outfit"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	for lane: StringName in LANES:
		s.actor(
			StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, LANES[lane][0]),
			{ "max_health": 10_000.0, "facing": Vector2.LEFT },
		)


func run(t: TestContext) -> void:
	await t.frames(3)
	for lane: StringName in LANES:
		var row: Array = LANES[lane]
		var shot := Shot.new()
		shot.height = row[1]
		shot.rise = row[2]
		ProjectileSpawner.spawn(
			Vector2(BODY_X - row[3] - 12.0, row[0]),
			Vector2.RIGHT,
			t.world,
			shot,
		)
	await t.seconds(0.6)
	var level := _lost(t, &"level")
	var pitched := _lost(t, &"pitched")
	t.check(level > 0.0, "the level round wounds (%.2f)" % level)
	t.expect_near(
		pitched, level, level * 0.02,
		"the pitched round deals the same (%.2f against %.2f)" % [pitched, level],
	)


func _lost(t: TestContext, lane: StringName) -> float:
	return 10_000.0 - t.actor(StringName("body_%s" % lane)).health
