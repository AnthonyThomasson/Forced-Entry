extends GameTest
## G8 (#194 D10): the fragments are 3D rays over the upper hemisphere, and an exposed standing body
## takes from them what it took when they flew level at a height drawn from the floor to the
## ceiling of the old scale: the same damage at each distance, in each band. Standing dummies stand
## in the open on a ring at each of four distances from a burst on the floor (six to a ring, the
## rings turned from one another so no dummy stands in another's line; the blast itself is switched
## off in the row: this reads the fragments alone); the burst goes off `BURSTS` times and each
## band's fragment damage is summed over its dummies and the bursts.

const AT := Vector2(700, 500)
const BURSTS := 100
## The distance bands (px): inside the kill radius, in the blast's mid, at its edge and out where
## the fragments' reach ends, the dummies of a ring this many degrees apart and each ring turned a
## further `TURN` degrees from the last.
const BANDS := [70.0, 140.0, 260.0, 420.0]
const DUMMIES := 6
const TURN := 15.0
## What an exposed standing body took per burst and dummy in each band when the fragments flew
## level at a height drawn between the floor and the top of the old scale (measured on that code
## over this scenario).
const TODAY := [15.06, 5.89, 4.11, 2.34]
## The share of that the rays' sum may stray from it: the fragments' count, damage and flatness are
## tuned to within about a tenth of it in every band, and the 100 bursts of six dummies leave about
## a tenth of spread in the far band's few hits.
const TOLERANCE := 0.2


func describe() -> Dictionary:
	return {
		"name": "A frag's fragments hurt an exposed standing body as they did, band by band",
		"description": "Standing dummies on rings of 70, 140, 260 and 420 px round a frag on the "
			+ "floor, over 100 bursts, each ring takes about what the level fragments dealt at "
			+ "that distance.",
		"tags": ["grenade", "frag", "fragments", "projectile", "g8"],
		"timeout": 200.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", Vector2(30, 30), { "max_health": 1.0e9 })
	for band in BANDS.size():
		for j in DUMMIES:
			s.actor(_id(band, j), &"puppet", _place(band, j), { "max_health": 1.0e9 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var row: Dictionary = (GrenadeConfig.grenades[&"frag"] as Dictionary).duplicate()
	row["blast_damage"] = 0.0
	row["blast_impulse"] = 0.0
	for _i in BURSTS:
		# the hits shove a dummy: each burst finds it where it stood
		for band in BANDS.size():
			for j in DUMMIES:
				var dummy := t.actor(_id(band, j))
				dummy.global_position = _place(band, j)
				dummy.velocity = Vector2.ZERO
		Explosion.frag(AT, t.world, thrower, row)
		await t.frames(14)
	for band in BANDS.size():
		var sum := 0.0
		for j in DUMMIES:
			var victim := t.actor(_id(band, j))
			for e in t.events_of(
					&"hit",
					func(d): return d.get("victim") == victim and d.get("outcome") != &"blast",
			):
				sum += float(e["damage"])
		var per := sum / (BURSTS * DUMMIES)
		var want: float = TODAY[band]
		t.check(
			absf(per - want) <= want * TOLERANCE,
			"band %d px: %.2f damage a burst and dummy (today %.2f)" % [
				int(BANDS[band]),
				per,
				want,
			],
		)


func _id(band: int, j: int) -> StringName:
	return StringName("band_%d_%d" % [band, j])


## Where dummy `j` of ring `band` stands.
func _place(band: int, j: int) -> Vector2:
	var angle := deg_to_rad(360.0 / DUMMIES * j + TURN * band)
	return AT + Vector2.from_angle(angle) * BANDS[band]
