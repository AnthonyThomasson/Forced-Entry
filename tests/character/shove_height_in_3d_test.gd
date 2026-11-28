extends GameTest
## A blow shoves a free piece at the height it lands (#194, interface 5): a punch lands at
## fist height, up the body of a tall thin bookshelf, and tips it over; the same punch only slides a
## low, wide sofa.

const Probe := preload("res://tests/_objects/piece_probe.gd")
## Hard enough, at the fist, to tip a bookshelf (a bare punch is a tenth of it).
const BLOW := 12_000.0
const FRONT := 50.0


func describe() -> Dictionary:
	return {
		"name": "A punch at fist height tips a bookshelf and only slides a sofa",
		"description": "A hard punch lands at fist height: a bookshelf leans past 60 degrees, a "
			+ "sofa slides upright.",
		"tags": ["melee", "punch", "pushable", "3d", "tipping", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterMeleeConfig, &"punch_impulse", BLOW)
	s.object(&"shelf", "bookshelf", Vector2(300, 100))
	s.object(&"sofa", "sofa", Vector2(300, 250))
	s.actor(&"boxer1", &"puppet", Vector2(300 - FRONT, 100), { "start_slot": 2 })
	s.actor(&"boxer2", &"puppet", Vector2(222, 250), { "start_slot": 2 })


func run(t: TestContext) -> void:
	await t.frames(3)
	var shelf: Node2D = t.object(&"shelf")
	var sofa: Node2D = t.object(&"sofa")
	if not t.require(Probe.body(shelf) != null, "premise: the bookshelf is a free 3D body"):
		return
	for pair: Array in [[&"boxer1", shelf], [&"boxer2", sofa]]:
		t.puppet(pair[0]).aim_at((pair[1] as Node2D).global_position)
	await t.seconds(0.3)
	var sofa_start := sofa.global_position
	t.puppet(&"boxer1").punch()
	t.puppet(&"boxer2").punch()
	await t.seconds(1.0)
	await Probe.settle(t, shelf, 6.0)
	await Probe.settle(t, sofa, 6.0)
	t.check(
		Probe.lean(shelf) > 60.0,
		"the punch at fist height tips the bookshelf (%.0f degrees)" % Probe.lean(shelf),
	)
	t.check(
		Probe.lean(sofa) < 10.0,
		"the same punch leaves the sofa upright (%.1f degrees)" % Probe.lean(sofa),
	)
	t.check(
		sofa.global_position.x - sofa_start.x > 10.0,
		"and slides it along (%.1f px)" % (sofa.global_position.x - sofa_start.x),
	)
