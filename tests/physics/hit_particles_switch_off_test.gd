extends GameTest
## With the `physics.hit_particles` switch off a shot bursts no particles (it still hits).

const FxTap := preload("res://tests/_physics/fx_tap.gd")
## A round aimed this low (px) meets a chair, a lamp or a car; a level one at the muzzle flies over.
const LOW := 10.0


func describe() -> Dictionary:
	return {
		"name": "A shot bursts nothing with hit particles off",
		"description": "A puppet shoots a chair with the hit-particles switch off; the chair is "
			+ "hit but no burst is made.",
		"tags": ["hit particles", "switch", "chair"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"physics.hit_particles", false)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))


func run(t: TestContext) -> void:
	var tap := FxTap.new().attach()
	var shooter := t.puppet(&"shooter")
	var chair := t.object(&"chair")
	shooter.aim_at(chair.global_position, LOW)
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(
			await t.until(func(): return not chair.hit_marks().is_empty(), 2.0),
			"the shot hits the chair",
	):
		return
	await t.seconds(0.3)
	tap.detach()
	t.check(tap.bursts.is_empty(), "no particle burst was made")
