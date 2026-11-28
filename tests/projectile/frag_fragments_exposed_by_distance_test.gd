extends GameTest
## G8 (#194 D10): the fragments are 3D rays over the upper hemisphere, and an exposed standing body
## loses from them (the HP, after the hit zone's share) what it lost when they flew level at a
## height drawn from the floor to the ceiling of the old scale: the same at each distance, in each
## band, and a spread over the
## body (not nearly all at the feet) so a vest or a helmet has fragments to stop (O9). Standing
## dummies stand in the open on a ring at each of four distances from a burst on the floor (six to a
## ring, the rings turned from one another so no dummy stands in another's line; the blast itself is
## switched off in the row: this reads the fragments alone); the burst goes off `BURSTS` times and
## each band's HP lost is summed over its dummies and the bursts.

const AT := Vector2(700, 500)
const BURSTS := 100
## The distance bands (px): inside the kill radius, in the blast's mid, at its edge and out where
## the fragments' reach ends, the dummies of a ring this many degrees apart and each ring turned a
## further `TURN` degrees from the last.
const BANDS := [70.0, 140.0, 260.0, 420.0]
const DUMMIES := 6
const TURN := 15.0
## The HP an exposed standing body lost per burst and dummy in each band when the fragments flew
## level, 12 damage each, at a height drawn between 2 and 123 px (the old scale's floor and
## ceiling), measured over this scenario (zone shares: feet and legs 0.6, torso 1, head 2). The
## figure before the zone's share, 15.06 / 5.89 / 4.11 / 2.34, is not what a body loses.
const TODAY := [14.28, 5.28, 4.03, 2.24]
## The share of that the rays' sum may stray from it: the fragments' damage and flatness are tuned
## to within 15% of it in every band (14% at most) (a flatter fan keeps the distance law, a steeper
## one spreads the hits up the body: a hit's chance falls as distance^-(1/flatness)), and the 100
## bursts of six dummies leave a few per cent of spread in the far band's few hits.
const TOLERANCE := 0.2
## The share of the fragment hits on a standing body that land on the torso or the head, over all
## the bands and in each (a fan nearly level would put them all on the feet and legs: 3 to 5% at
## flatness 12, where the old level draw gave 49%), and the most that land on the feet.
const MIN_UPPER_SHARE := 0.08
const MIN_UPPER_SHARE_BAND := 0.05
const MAX_FEET_SHARE := 0.55


func describe() -> Dictionary:
	return {
		"name": "A frag's fragments hurt an exposed standing body as they did, band by band",
		"description": "Standing dummies on rings of 70, 140, 260 and 420 px round a frag on the "
			+ "floor, over 100 bursts, each ring takes about what the level fragments dealt at "
			+ "that distance, and the hits spread up the body.",
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
				dummy.movement.velocity = Vector2.ZERO
		Explosion.frag(AT, t.world, thrower, row)
		await t.frames(14)
	var upper_all := 0
	var all := 0
	for band in BANDS.size():
		var tally := _tally(t, band)
		_check_band(t, band, tally)
		upper_all += tally["upper"]
		all += tally["hits"]
	t.check(upper_all >= MIN_UPPER_SHARE * all, (
		"over every band %d of %d hits (%.1f%%) are on the torso or head (at least %.0f%%)"
		% [upper_all, all, 100.0 * upper_all / maxf(all, 1), MIN_UPPER_SHARE * 100.0]
	))


## What ring `band`'s dummies took from the fragments: the HP lost, the hits, and how many of them
## struck the torso or head and the feet.
func _tally(t: TestContext, band: int) -> Dictionary:
	var out := { "damage": 0.0, "hits": 0, "upper": 0, "feet": 0 }
	for j in DUMMIES:
		var victim := t.actor(_id(band, j))
		out["damage"] += victim.max_health - victim.health
		for e in t.events_of(
				&"hit",
				func(d): return d.get("victim") == victim and d.get("outcome") != &"blast",
		):
			out["hits"] += 1
			var zone := BodyHeights.zone_at(BodyHeights.STAND, float(e["height"]))
			out["upper"] += int(zone == &"torso" or zone == &"head")
			out["feet"] += int(zone == &"feet")
	return out


## The checks of one band: its HP against today's, and how its hits spread up the body.
func _check_band(t: TestContext, band: int, tally: Dictionary) -> void:
	var per: float = tally["damage"] / (BURSTS * DUMMIES)
	var want: float = TODAY[band]
	var px := int(BANDS[band])
	t.check(
		absf(per - want) <= want * TOLERANCE,
		"band %d px: %.2f HP a burst and dummy (today %.2f)" % [px, per, want],
	)
	t.check(tally["hits"] > 0 and tally["upper"] >= MIN_UPPER_SHARE_BAND * tally["hits"], (
		"band %d px: %d of %d hits on the torso or head (at least %.0f%%)"
		% [px, tally["upper"], tally["hits"], MIN_UPPER_SHARE_BAND * 100.0]
	))
	t.check(tally["feet"] <= MAX_FEET_SHARE * tally["hits"], (
		"band %d px: %d of %d hits on the feet (at most %.0f%%)"
		% [px, tally["feet"], tally["hits"], MAX_FEET_SHARE * 100.0]
	))


func _id(band: int, j: int) -> StringName:
	return StringName("band_%d_%d" % [band, j])


## Where dummy `j` of ring `band` stands.
func _place(band: int, j: int) -> Vector2:
	var angle := deg_to_rad(360.0 / DUMMIES * j + TURN * band)
	return AT + Vector2.from_angle(angle) * BANDS[band]
