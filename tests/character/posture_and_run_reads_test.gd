extends GameTest
## Interface 7: what a controller may ask of a character about its own body, instead of keeping a
## copy of the numbers: `movement.run_speed()` (px/s, running standing: what the character really
## covers, so a controller can tell whether it gets somewhere in time). Pinned against what the body
## does. (A posture's height is `BodyHeights`' real one, `tests/general/body_heights_test.gd`.)

const SPEED_SLACK := 0.06


func describe() -> Dictionary:
	return {
		"name": "A character tells its running speed",
		"description": "run_speed is the speed the character really covers running, and falls "
			+ "while it is stunned.",
		"tags": ["character", "posture", "run"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 500))
	s.actor(&"c", &"puppet", Vector2(100, 250), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var c := t.actor(&"c")

	# Run along the arena and measure the speed it covers.
	var puppet := t.puppet(&"c")
	puppet.set_run(true)
	puppet.walk(Vector2.RIGHT)
	await t.seconds(0.3)
	var from: Vector2 = c.global_position
	var start := t.time
	await t.seconds(0.6)
	var measured: float = from.distance_to(c.global_position) / (t.time - start)
	t.check(c.movement.is_running(), "set-up: it is running")
	t.check(
		absf(c.movement.run_speed() - measured) <= c.movement.run_speed() * SPEED_SLACK,
		"run_speed() %.0f px/s is what it covers running (%.0f measured)"
			% [c.movement.run_speed(), measured],
	)
	t.check(
		c.movement.run_speed() > c.movement.speed * 1.3,
		"faster than its walk (%.0f px/s)" % c.movement.speed,
	)
	puppet.stop()
	var free: float = c.movement.run_speed()
	c.take_stun(2.0, 0.0)
	t.check(
		c.movement.run_speed() < free,
		"and slower while stunned (%.0f against %.0f)" % [c.movement.run_speed(), free],
	)
