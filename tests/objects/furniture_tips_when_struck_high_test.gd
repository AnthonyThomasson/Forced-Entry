extends GameTest
## A free piece of furniture is a real 3D body (#194 furn3d, D13): a bookshelf struck high by a
## round leans over and lies on its side, where a sofa struck as hard low down only slides and stays
## upright (physics decides, from mass, footprint and where the push lands).

const Probe := preload("res://tests/_objects/piece_probe.gd")
## A round meets the shelf up near its top (px above the floor): the bookshelf stands about 77 px.
const HIGH := 52.0
const LOW := 8.0


func describe() -> Dictionary:
	return {
		"name": "A bookshelf struck high tips over and a sofa struck low only slides",
		"description": "A rifle burst meets a bookshelf near its top: it leans past 60 degrees, "
			+ "comes to rest asleep lying on its side, its top far lower than standing. A sofa "
			+ "shot low by the same burst stays within a few degrees of upright.",
		"tags": ["furniture", "3d", "tipping", "knockback", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.actor(&"shooter", &"puppet", Vector2(120, 140), { "start_slot": 6 })
	s.actor(&"shooter2", &"puppet", Vector2(120, 360), { "start_slot": 6 })
	s.object(&"shelf", "bookshelf", Vector2(600, 140))
	s.object(&"sofa", "sofa", Vector2(600, 360))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var shelf := t.object(&"shelf")
	var sofa := t.object(&"sofa")
	if not t.require(Probe.body(shelf) != null, "premise: the bookshelf has a free 3D body"):
		return
	var standing := Probe.top(shelf)
	t.require(standing > 50.0, "premise: the bookshelf stands tall (%.1f px)" % standing)
	var gun := t.puppet(&"shooter")
	var gun2 := t.puppet(&"shooter2")
	gun.aim_at(shelf.global_position, HIGH)
	gun2.aim_at(sofa.global_position, LOW)
	await t.seconds(0.5)
	gun.hold_fire(true)
	gun2.hold_fire(true)
	await t.seconds(1.4)
	gun.hold_fire(false)
	gun2.hold_fire(false)
	await Probe.settle(t, shelf, 8.0)
	await Probe.settle(t, sofa, 8.0)
	t.check(
		Probe.lean(shelf) > 60.0,
		"the bookshelf leaned over (%.0f degrees from upright)" % Probe.lean(shelf),
	)
	t.check(
		Probe.top(shelf) < standing * 0.7,
		"lying on its side its top is lower (%.1f of %.1f px)" % [Probe.top(shelf), standing],
	)
	t.check(Probe.asleep(shelf), "it came to rest")
	t.check(
		Probe.lean(sofa) < 10.0,
		"the sofa stayed upright (%.1f degrees)" % Probe.lean(sofa),
	)
	t.check(
		sofa.global_position.distance_to(Vector2(600, 360)) > 1.0,
		"and slid a little (%.1f px)" % sofa.global_position.distance_to(Vector2(600, 360)),
	)
