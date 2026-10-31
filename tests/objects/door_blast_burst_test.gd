extends GameTest
## DR10: a blast on a shut door from the side it swings away from wears its latch like a kick, and a
## frag's close blast gives a steel door's latch, which no kick does: the steel door bursts fully
## open. From the side it swings toward the blast only damages it and it stays shut. Both steel
## doors swing east; one frag lands 50 px west of the first (its push side), one 50 px east of the
## second (its pull side).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const JAMB := 20.0
const PUSH_DOOR := Vector2(400, 200)
const PULL_DOOR := Vector2(1600, 200)
const BURST := 0.4


func describe() -> Dictionary:
	return {
		"name": "A blast from the push side bursts a steel door open",
		"description": "A frag landing close on a steel door's push side bursts it fully open; "
			+ "one landing on its pull side only damages it.",
		"tags": ["door", "objects", "burst", "grenade"],
		"timeout": 16.0,
	}


func _doorway(at: Vector2, id: String) -> Dictionary:
	return {
		"pos": at, "width": 52.0,
		"door": {
			"name": id, "material": "steel", "style": "riveted",
			"hinge": at - Vector2(0, JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 400) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 400) },
		{ "key": "west_b", "type": "living_room", "rect": Rect2(1200, 0, 400, 400) },
		{ "key": "east_b", "type": "bedroom", "rect": Rect2(1600, 0, 400, 400) },
	], [_doorway(PUSH_DOOR, "pushed"), _doorway(PULL_DOOR, "pulled")])
	s.von_down()
	s.actor(&"thrower_push", &"puppet", Vector2(110, 200), { "max_health": 100_000.0 })
	s.actor(&"thrower_pull", &"puppet", Vector2(1990, 200), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"thrower_push"), 0, 1)
	Probe.arm(t.actor(&"thrower_pull"), 0, 1)
	await Probe.throw_at(t, &"thrower_push", Probe.FRAG, PUSH_DOOR - Vector2(50, 0))
	await Probe.throw_at(t, &"thrower_pull", Probe.FRAG, PULL_DOOR + Vector2(50, 0))
	if not t.require(
			await t.until(func(): return Probe.booms(t, &"frag").size() >= 2, 8.0),
			"both frags go off",
	):
		return
	var pushed = t.object(&"pushed")
	var pulled = t.object(&"pulled")
	for door in [pushed, pulled]:
		var blasted := func(d: Dictionary) -> bool:
			return d["victim"] == door and d["outcome"] == &"blast"
		t.check(t.happened(&"hit", blasted), "the blast struck the %s door" % door.name)
	t.check(
		await t.until(func(): return pushed.angle() >= 89.0, BURST),
		"a blast on its push side bursts a steel door fully open (angle %.0f)" % pushed.angle(),
	)
	await t.seconds(0.5)
	t.check(pulled.angle() == 0.0, "from its pull side it stays shut (angle %.0f)" % pulled.angle())
	t.check(pulled.damage.hp < pulled.damage.max_hp, "though the blast marks it")
