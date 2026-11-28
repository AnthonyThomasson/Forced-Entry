extends GameTest
## An item is its own body (#194, D20, `docs/stacked-items.md`): a shove on the box at the
## top of a stack of three moves only that box; the crates under it stay where they are, asleep.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(400, 250)


func describe() -> Dictionary:
	return {
		"name": "A box shoved off the top of a stack moves alone",
		"description": "A box on a crate on a crate is shoved sideways at its middle: it slides "
			+ "off toward +x while both crates stay put, asleep.",
		"tags": ["furniture", "3d", "items", "stacking", "pushable"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"low", "crate", AT)
	s.object(&"mid", "crate", Vector2.ZERO, { "on": &"low" })
	s.object(&"high", "box", Vector2.ZERO, { "on": &"mid" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id in [&"low", &"mid", &"high"]:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "premise: %s asleep" % id):
			return
	var low_at: Vector2 = t.object(&"low").global_position
	var mid_at: Vector2 = t.object(&"mid").global_position
	var high_at: Vector2 = t.object(&"high").global_position
	Knockback.push(t.object(&"high"), Vector2(900.0, 0.0), Vector2.ZERO, 38.0)
	await t.seconds(0.6)
	t.check(
		t.object(&"high").global_position.x - high_at.x > 4.0,
		"the shoved box slid off toward +x (%.1f px)"
			% (t.object(&"high").global_position.x - high_at.x),
	)
	t.check(
		t.object(&"mid").global_position.distance_to(mid_at) < 0.5,
		"the crate under it did not move (%.2f px)"
			% t.object(&"mid").global_position.distance_to(mid_at),
	)
	t.check(
		t.object(&"low").global_position.distance_to(low_at) < 0.5,
		"nor did the crate at the bottom (%.2f px)"
			% t.object(&"low").global_position.distance_to(low_at),
	)
	t.check(Probe.asleep(t.object(&"mid")), "the crate under it is still asleep")
