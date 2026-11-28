extends GameTest
## G3: a grenade can land on top of furniture. A stun thrown at a desk's middle comes to rest on the
## desk's top (31 px up), not on the floor beside it, and goes off there.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const DESK := Vector2(300, 100)
const FROM := Vector2(100, 100)
## the desk's footprint and top
const HALF := Vector2(60, 25)
const TOP := 31.0


func describe() -> Dictionary:
	return {
		"name": "A grenade thrown at a desk lands on top of it",
		"description": "A stun thrown at the middle of a desk comes to rest on the desk's top, "
			+ "31 px up inside its footprint, and goes off there.",
		"tags": ["grenade", "land", "furniture", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun"):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, DESK)
	var flight := await Probe.track(t, 4.0)
	if not t.require(flight.size() > 10, "a grenade flew"):
		return
	var last: Dictionary = flight.back()
	var at: Vector2 = last["at"]
	t.check(
		absf(at.x - DESK.x) <= HALF.x and absf(at.y - DESK.y) <= HALF.y,
		"it lies within the desk's footprint (%s)" % str(at.round()),
	)
	t.check(
		float(last["altitude"]) > TOP - 4.0,
		"on its top (%.0f px up, the top at %.0f)" % [last["altitude"], TOP],
	)
