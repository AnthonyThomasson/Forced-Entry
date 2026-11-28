extends GameTest
## The pushable contract takes a height (#194, D13; interface 5): `Knockback.push` shoves a
## free piece at its real 3D point. The same shove that leaves a low heavy sofa sliding upright lays
## a tall thin bookshelf on its side when it lands high on it, and only slides it when it lands at
## its middle (its centre of mass); a shove given no height only slides a piece, as it did in 2D.

const Probe := preload("res://tests/_objects/piece_probe.gd")
## The shove (impulse px x mass / s) every piece gets.
const SHOVE := Vector2(5000.0, 0.0)


func describe() -> Dictionary:
	return {
		"name": "A shove at height tips a tall piece and only slides a low one",
		"description": "One 5000 shove along +x: on a bookshelf near its top it lays it over; on "
			+ "the same bookshelf at its middle it slides it upright; on a sofa it slides it; "
			+ "with no height it slides the shelf without a tip.",
		"tags": ["furniture", "3d", "tipping", "knockback", "pushable"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.object(&"shelf_high", "bookshelf", Vector2(150, 100))
	s.object(&"shelf_low", "bookshelf", Vector2(150, 250))
	s.object(&"shelf_none", "bookshelf", Vector2(150, 400))
	s.object(&"sofa", "sofa", Vector2(150, 560))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var high := t.object(&"shelf_high")
	var low := t.object(&"shelf_low")
	var none := t.object(&"shelf_none")
	var sofa := t.object(&"sofa")
	Knockback.push(high, SHOVE, Vector2.ZERO, Probe.top(high) - 4.0)
	Knockback.push(low, SHOVE, Vector2.ZERO, Probe.top(low) * 0.5)
	Knockback.push(none, SHOVE)
	Knockback.push(sofa, SHOVE, Vector2.ZERO, 30.0)
	await t.seconds(0.3)  # the shoves wake them (the node's `sleeping` reads the last step)
	for piece in [high, low, none, sofa]:
		await Probe.settle(t, piece, 10.0)
	t.check(
		Probe.lean(high) > 60.0,
		"high on the shelf: it lies over (%.0f degrees)" % Probe.lean(high),
	)
	t.check(Probe.lean(low) < 15.0, "at its middle: it stays up (%.0f degrees)" % Probe.lean(low))
	t.check(
		(low.global_position - Vector2(150, 250)).x > 3.0,
		"and slides along the shove (%.1f px)" % (low.global_position.x - 150.0),
	)
	t.check(
		Probe.lean(none) < 15.0,
		"with no height it is not tipped (%.0f degrees)" % Probe.lean(none),
	)
	t.check(Probe.lean(sofa) < 10.0, "the sofa slides upright (%.0f degrees)" % Probe.lean(sofa))
	t.check(
		(sofa.global_position - Vector2(150, 560)).x > 3.0,
		"it slid (%.1f px)" % (sofa.global_position.x - 150.0),
	)
