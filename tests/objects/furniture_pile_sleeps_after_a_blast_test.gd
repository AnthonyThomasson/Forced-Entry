extends GameTest
## A house's furniture blasted about settles (#194 furn3d, D13; the phase-1 spike's pile, on the
## real catalogue): a few frags go off among a furnished house's pieces; every free piece is asleep
## again within `SETTLE` s (Jolt's sleep: a tipped pile that never slept would cost the 3D step a
## frame forever), some have tipped, and none has fallen out of the house.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
const SEED := 7
const PLAN := "garage_home"
## How long (sim s) the whole house may take to come to rest.
const SETTLE := 10.0


func describe() -> Dictionary:
	return {
		"name": "A blasted house's furniture comes to rest asleep",
		"description": "Four frags go off at chest height among a furnished house: every piece "
			+ "is asleep within 10 s, some lie tipped, and none is under the floor or out of the "
			+ "house.",
		"tags": ["furniture", "3d", "tipping", "blast", "sleep", "perf"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	await t.seconds(0.5)
	var pieces: Array[Node] = []
	for body in PlanProbe.pieces_under(house):
		if Probe.body(body) != null:
			pieces.append(body)
	if not t.require(
		pieces.size() >= 20,
		"premise: a furnished house (%d free pieces)" % pieces.size(),
	):
		return
	t.require(
		pieces.all(func(piece: Node) -> bool: return Probe.asleep(piece)),
		"premise: every free piece is asleep before the blast",
	)
	var bounds := Rect2()
	for body in pieces:
		bounds = bounds.expand((body as Node2D).global_position)
	var row := GrenadeConfig.row(&"frag")
	var spots := [0.3, 0.45, 0.6, 0.75]
	for share in spots:
		var at := bounds.position + bounds.size * Vector2(share, 0.5)
		Explosion.frag(at, t.world, null, row, 40.0)
	await t.seconds(0.3)
	t.require(
		_awake(pieces).size() >= 3,
		"premise: the blasts woke pieces (%d)" % _awake(pieces).size(),
	)
	var came_to_rest := await t.until(
		func() -> bool: return pieces.all(func(piece: Node) -> bool: return Probe.asleep(piece)),
		SETTLE,
	)
	var awake := _awake(pieces)
	t.check(came_to_rest, "every piece is asleep within %.0f s (%d awake)" % [SETTLE, awake.size()])
	var tipped := pieces.filter(func(piece: Node) -> bool: return Probe.lean(piece) > 45.0)
	t.check(tipped.size() >= 1, "some lie tipped (%d)" % tipped.size())
	var lost := _lost(pieces, bounds)
	t.check(lost.is_empty(), "none fell out of the world (%d)" % lost.size())


## The pieces that fell through the floor or were flung far from the house's bounds.
func _lost(pieces: Array[Node], bounds: Rect2) -> Array:
	return pieces.filter(
		func(piece: Node) -> bool:
			var lead := Probe.body(piece)
			return lead.global_position.y < -2.0 or not bounds.grow(400.0).has_point(
				(piece as Node2D).global_position
			)
	)


## The pieces that are not asleep.
func _awake(pieces: Array[Node]) -> Array:
	return pieces.filter(func(piece: Node) -> bool: return not Probe.asleep(piece))
