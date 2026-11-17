extends GameTest
## A pistol round that goes through a character bursts particles at both the entry and the exit: one
## on the side the round came from, one on the far side, thrown onward.

const FxTap := preload("res://tests/_physics/fx_tap.gd")


func describe() -> Dictionary:
	return {
		"name": "A shot through a body bursts at entry and exit",
		"description": "A puppet shoots through another; one burst is made on the near side of the "
			+ "target and another on the far side.",
		"tags": ["hit particles", "penetration", "pistol", "blood"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(150, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(450, 200), { "max_health": 400.0 })


func run(t: TestContext) -> void:
	var tap := FxTap.new().attach()
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	shooter.aim_at(target)
	await t.seconds(0.5)
	shooter.shoot()
	var twice: bool = await t.until(func(): return tap.bursts.size() >= 2, 2.0)
	tap.detach()
	if not t.require(twice, "the shot bursts particles twice"):
		return
	var xs: Array = tap.bursts.map(func(b): return b["at"].x).filter(
		func(x): return x < target.global_position.x + 60.0,
	)
	t.check(
		xs.min() < target.global_position.x,
		"one burst is on the near side of the target (%s)" % str(xs),
	)
	var near: Dictionary = tap.bursts.filter(
		func(b): return b["at"].x < target.global_position.x,
	)[0]
	var far: Dictionary = tap.bursts.filter(func(b): return (
		b["at"].x > target.global_position.x
			and b["at"].x < target.global_position.x + 60.0
	))[0]
	t.check(
		far["amount"] >= near["amount"] * 2,
		"the exit burst is much stronger than the entry (%d vs %d particles)"
			% [far["amount"], near["amount"]],
	)
	t.check(
		far["speed_max"] > near["speed_max"],
		"the exit burst is thrown harder than the entry",
	)
	t.check(
		xs.max() > target.global_position.x,
		"one burst is on the far side of the target (%s)" % str(xs),
	)
