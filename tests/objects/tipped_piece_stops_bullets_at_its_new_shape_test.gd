extends GameTest
## A tipped piece is its twin (#194 furn3d, D14): geometry follows. A bookshelf knocked over lies
## across the floor, so a level round at the height it stood to no longer meets it and a low one
## does, where it now lies, not where it stood; and its 2D footprint (what the nav reads) is the
## projection of where it lies.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(500, 250)
const HIGH := 60.0
const LOW := 10.0


func describe() -> Dictionary:
	return {
		"name": "A tipped bookshelf stops bullets where it lies",
		"description": "A bookshelf is knocked over toward +x; a round at 60 px up through its "
			+ "old place passes, a round at 10 px up through where it lies is stopped by it, and "
			+ "its footprint now reaches as far as it lies.",
		"tags": ["furniture", "3d", "tipping", "bullets", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.actor(&"shooter", &"puppet", Vector2(120, 250), { "start_slot": 3 })
	s.object(&"shelf", "bookshelf", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var shelf := t.object(&"shelf")
	var standing := Probe.top(shelf)
	t.require(standing > 70.0, "premise: it stands tall (%.1f px)" % standing)
	var before := _blocked_at(t, AT, HIGH)
	t.require(before, "premise: standing, it stops a level ray at %.0f px" % HIGH)
	# knock it over toward +x: a hard shove near the top
	Knockback.push(shelf, Vector2(9000.0, 0.0), Vector2.ZERO, standing - 6.0)
	await t.seconds(0.2)
	await Probe.settle(t, shelf, 10.0)
	if not t.require(
			Probe.lean(shelf) > 70.0,
			"premise: it lies on its side (%.0f degrees)" % Probe.lean(shelf),
	):
		return
	var rests: Vector2 = shelf.global_position
	t.check(
		not _blocked_at(t, rests, HIGH),
		"a level ray at the height it stood, through where it lies, passes",
	)
	t.check(
		_blocked_at(t, rests, LOW),
		"a level ray low down through where it lies is stopped by it",
	)
	t.check(Probe.top(shelf) < 50.0, "its top is far lower now (%.1f px)" % Probe.top(shelf))
	# a real round, low, along the floor from the gun: it hits the shelf lying where it does
	var gun := t.puppet(&"shooter")
	gun.aim_at(rests, LOW)
	await t.seconds(0.5)
	gun.shoot()
	t.check(
		await t.until(
			func(): return t.happened(&"hit", func(d): return d["victim"] == shelf), 2.0,
		),
		"a pistol round aimed low hits the shelf where it lies",
	)
	# its footprint (the hull the nav carves, read off its twin) is where and as long as it lies
	var reach := 0.0
	for point in NavHoles.cut(shelf):
		reach = maxf(reach, point.distance_to(rests))
	t.check(reach > 30.0, "its footprint reaches %.0f px from where it rests" % reach)


## Whether a ray flown level at `height` px across plan point `at` (from 100 px either side of it
## along x) meets the shelf.
func _blocked_at(t: TestContext, at: Vector2, height: float) -> bool:
	var hit := Probe.ray_level(t, at - Vector2(100, 0), at + Vector2(100, 0), height)
	return not hit.is_empty() and hit["owner"] == t.object(&"shelf")
