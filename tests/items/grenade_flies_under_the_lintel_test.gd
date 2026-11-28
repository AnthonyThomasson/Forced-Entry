extends GameTest
## G3, a throw through a doorway: a doorway is open only as high as its door (84 px, a lintel over
## it to the wall's top, 96), so the arc the planner (`GrenadeArc`) throws through it is the lowest
## that reaches, flat enough to pass under. A stun thrown 520 px across a room and out of its
## doorway, 150 px along, passes the doorway lower than the lintel and lands in the next room at
## the aim.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const WALL_X := 400.0
const FROM := Vector2(250, 400)
## In the east room, 520 px along the doorway's line.
const AIM := Vector2(770, 400)
## A door's height, the lintel's underside.
const LINTEL := 84.0


func describe() -> Dictionary:
	return {
		"name": "A grenade thrown through a doorway flies under the lintel",
		"description": "Thrown 520 px through a doorway 150 px along, a stun passes it lower than "
			+ "the lintel's underside and comes to rest in the next room near the aim.",
		"tags": ["grenade", "lob", "doorway", "lintel", "item", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(400, 0, 400, 800) },
	], [{ "pos": Vector2(WALL_X, 400), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 1, 0)
	if not t.require(Probe.count(thrower, Probe.STUN) == 1, "the thrower carries a stun"):
		return
	await Probe.throw_at(t, &"thrower", Probe.STUN, AIM)
	var flight := await Probe.track(t, 4.0)
	if not t.require(not flight.is_empty(), "a grenade flew"):
		return
	var at_door := 0.0
	var crossed := false
	for sample: Dictionary in flight:
		var x: float = sample["at"].x
		if absf(x - WALL_X) <= 12.0:
			crossed = true
			at_door = maxf(at_door, float(sample["altitude"]))
	t.require(crossed, "premise: the grenade was seen at the doorway")
	t.check(
		at_door < LINTEL - GrenadeConfig.radius,
		"it passed the doorway under the lintel (%.0f px up, the lintel at %.0f)" % [
			at_door,
			LINTEL,
		],
	)
	var rest: Vector2 = flight.back()["at"]
	t.check(
		rest.x > WALL_X and rest.distance_to(AIM) < 100.0,
		"and landed in the next room near the aim (%.0f px off, x %.0f)"
			% [rest.distance_to(AIM), rest.x],
	)
