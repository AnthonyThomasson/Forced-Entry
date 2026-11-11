extends GameTest
## G7: the frag blast strikes the bodies it reaches nearest first, whatever order the engine's shape
## query lists them in (which follows what the process allocated before, so a replayed fight would
## otherwise draw its random numbers for a different body each run). Five chairs round the blast,
## created in an order that is not their order of distance, are struck in the order of their
## distance from it.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const FROM := Vector2(100, 450)
const AIM := Vector2(500, 450)
## The chairs: name, distance from the blast point, direction (degrees). Created in this order,
## which is no order of distance; the directions differ so none stands in another's line.
const CHAIRS := [
	[&"c1", 190.0, 20.0],
	[&"c2", 70.0, 110.0],
	[&"c3", 150.0, 200.0],
	[&"c4", 110.0, 290.0],
	[&"c5", 230.0, 65.0],
]


func describe() -> Dictionary:
	return {
		"name": "A frag blast strikes the bodies nearest first",
		"description": "Five chairs round a frag, created far and near mixed, are struck by "
			+ "the blast in the order of their distance from it.",
		"tags": ["grenade", "frag", "blast", "order"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 1000))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })
	for c: Array in CHAIRS:
		s.object(c[0], "chair", AIM + Vector2.from_angle(deg_to_rad(c[2])) * c[1])


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag grenade"):
		return
	var placed := {}  # chair -> where it stood before the blast shoved it
	for c: Array in CHAIRS:
		placed[t.object(c[0])] = (t.object(c[0]) as Node2D).global_position
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag grenade goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.seconds(0.3)
	var struck: Array = []
	for hit: Dictionary in Probe.raw(
			t, &"hit", func(d: Dictionary) -> bool: return d.get("outcome") == &"blast"):
		var victim: Node2D = hit["data"]["victim"]
		if CHAIRS.any(func(c: Array) -> bool: return t.object(c[0]) == victim):
			struck.append(victim)
	if not t.require(
			struck.size() == CHAIRS.size(), "every chair is struck (%d of 5)" % struck.size()):
		return
	var by_distance := struck.duplicate()
	by_distance.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return placed[a].distance_to(blast) < placed[b].distance_to(blast))
	t.check(
		struck == by_distance,
		"struck in the order of distance: %s, not %s"
			% [by_distance.map(func(n): return n.name), struck.map(func(n): return n.name)],
	)
