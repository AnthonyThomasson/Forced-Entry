extends GameTest
## G8 (#194 D10): a frag bursts where the grenade is, at its real height: one at rest on a desk
## goes off at the desk's top (31 px, and the grenade's centre over it), not at the floor under
## it. Its fragments leave from there, so they clear the desk top and none strikes the desk
## itself (from the floor they would strike its side).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DESK := Vector2(300, 100)
const FROM := Vector2(100, 100)
const TOP := 31.0


func describe() -> Dictionary:
	return {
		"name": "A frag lying on a desk bursts at the desk's height, its fragments clear the top",
		"description": "A frag thrown onto a desk rests on its 31 px top and goes off there: "
			+ "every fragment starts at least that high and none strikes the desk.",
		"tags": ["grenade", "frag", "fragments", "altitude", "3d"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var desk := t.object(&"desk")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	await Probe.throw_at(t, &"thrower", Probe.FRAG, DESK)
	var lowest := INF
	var count := 0
	var rested := false
	while t.time < 8.0 and count == 0:
		var group := t.world.get_children().filter(
			func(n): return String(n.name).begins_with("Projectile") and n is Node2D,
		)
		for p in group:
			lowest = minf(lowest, float(p.height))
		count = group.size()
		rested = rested or not Probe.raw(
			t, &"grenade", func(d): return d.get("stage") == &"rest",
		).is_empty()
		await t.frames(1)
	if not t.require(count > 0, "the frag went off and threw its fragments"):
		return
	t.check(rested, "the grenade came to rest first")
	t.check(
		lowest >= TOP,
		"every fragment starts at the desk's height or above (lowest %.1f px, the top %.0f)"
			% [lowest, TOP],
	)
	await t.seconds(1.0)
	var on_desk := t.events_of(
		&"hit",
		func(d): return d.get("victim") == desk and d.get("outcome") != &"blast",
	)
	t.expect_eq(on_desk.size(), 0, "no fragment strikes the desk it went off on")
