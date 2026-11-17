extends GameTest
## A pistol shot that strikes a chair bursts particles at the entry point (HitParticles): one burst
## at full strength, told to the 3D render.

const FxTap := preload("res://tests/_physics/fx_tap.gd")


func describe() -> Dictionary:
	return {
		"name": "A shot bursts particles at the entry",
		"description": "A puppet shoots a chair; one burst of particles is made at the "
			+ "chair's near face.",
		"tags": ["hit particles", "hittable", "pistol", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	# no exit is found: the round just lands in the chair
	s.set_static(BallisticsPenetrationConfig, "exit_probe_distance", 0.0)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


func run(t: TestContext) -> void:
	var tap := FxTap.new().attach()
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	var chair_at: Vector2 = chair.global_position
	shooter.aim_at(chair_at)
	await t.seconds(0.5)
	shooter.shoot()
	var burst_made: bool = await t.until(func(): return tap.bursts.size() > 0, 2.0)
	await t.seconds(0.3)
	tap.detach()
	if not t.require(burst_made, "the shot bursts particles"):
		return
	# The round that stays in the chair is the only one that bursts at the chair; one that flew on
	# bursts on the far wall.
	var at_chair: Array = tap.bursts_near(chair_at, 60.0)
	# No exit is found, so the round stays in the chair: one burst, at the full (exit-level)
	# strength.
	t.expect_eq(at_chair.size(), 1, "a hit that stays in the object gets a single burst")
	var burst: Dictionary = at_chair[0]
	t.check(
		burst["amount"] >= 8,
		"a lone impact bursts at full strength (%d particles)" % burst["amount"],
	)
	t.expect_near(
		burst["at"].x,
		chair_at.x,
		40.0,
		"the burst starts at the chair",
	)
