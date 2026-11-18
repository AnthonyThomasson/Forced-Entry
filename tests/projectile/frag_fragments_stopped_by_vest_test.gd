extends GameTest
## O9 (docs/outfits.md), G8 (#194): a frag's fragments are rays that strike a body at a height, so a
## tactical vest's soft panel stops those that meet the torso. Two rings of six standing dummies 140
## px from a burst, one bare and one in a vest (the blast switched off, so only the fragments hurt),
## over 80 bursts: the bare ring is struck and never "blocked", the vested ring has fragments
## blocked by the armour and takes clearly less damage.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const BURSTS := 80
const DISTANCE := 140.0
const DUMMIES := 6
const BARE_AT := Vector2(350, 500)
const VEST_AT := Vector2(1050, 500)
## The most the vested ring may take of what the bare one does.
const MAX_SHARE := 0.92
## What a hit the armour stopped names as the struck surface (flesh stops a slow fragment too).
const ARMOUR_MATERIALS := ["fabric", "composite", "ceramic", "metal"]


func describe() -> Dictionary:
	return {
		"name": "A vest stops some of a frag's fragments",
		"description": "Over 80 frag bursts (the blast switched off) a ring of bare standing "
			+ "dummies is struck and a ring in tactical vests has fragments blocked by the vest "
			+ "and takes less damage.",
		"tags": ["outfit", "armour", "grenade", "frag", "fragments", "g8", "o9"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 1000))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", Vector2(30, 30), { "max_health": 1.0e9 })
	for j in DUMMIES:
		s.actor(_id("bare", j), &"puppet", _place(BARE_AT, j), { "max_health": 1.0e9 })
		s.actor(_id("vest", j), &"puppet", _place(VEST_AT, j), { "max_health": 1.0e9 })


func run(t: TestContext) -> void:
	if not OutfitProbe.require_api(t, t.actor(_id("vest", 0))):
		return
	for j in DUMMIES:
		OutfitProbe.wear(t.actor(_id("vest", j)), { "vest": &"tactical_vest" })
	await t.seconds(0.3)
	var row: Dictionary = (GrenadeConfig.grenades[&"frag"] as Dictionary).duplicate()
	row["blast_damage"] = 0.0
	row["blast_impulse"] = 0.0
	for _i in BURSTS:
		# the hits shove a dummy: each burst finds it where it stood
		for j in DUMMIES:
			for pair: Array in [["bare", BARE_AT], ["vest", VEST_AT]]:
				var dummy := t.actor(_id(pair[0], j))
				dummy.global_position = _place(pair[1], j)
				dummy.velocity = Vector2.ZERO
		Explosion.frag(BARE_AT, t.world, t.actor(&"thrower"), row)
		Explosion.frag(VEST_AT, t.world, t.actor(&"thrower"), row)
		await t.frames(14)
	var bare := _tally(t, "bare")
	var vest := _tally(t, "vest")
	t.check(bare["hits"] > 50, "the bare ring is struck (%d fragments)" % bare["hits"])
	t.expect_eq(bare["blocked"], 0, "no fragment is blocked by a bare body")
	t.check(
		vest["blocked"] > 0,
		"the vests block fragments (%d of %d)" % [vest["blocked"], vest["hits"] + vest["blocked"]],
	)
	t.check(
		vest["damage"] < bare["damage"] * MAX_SHARE,
		"the vested ring takes clearly less (%.0f against %.0f bare)"
			% [vest["damage"], bare["damage"]],
	)


## What the ring `kind` took from the fragments: hits that struck flesh, hits the armour blocked
## and the damage the ring lost.
func _tally(t: TestContext, kind: String) -> Dictionary:
	var out := { "hits": 0, "blocked": 0, "damage": 0.0 }
	for j in DUMMIES:
		var body := t.actor(_id(kind, j))
		out["damage"] += body.max_health - body.health
		for e in t.events_of(
				&"hit",
				func(d): return d.get("victim") == body and d.get("outcome") != &"blast",
		):
			if e["outcome"] == &"blocked" and e["material"] in ARMOUR_MATERIALS:
				out["blocked"] += 1
			else:
				out["hits"] += 1
	return out


func _id(kind: String, j: int) -> StringName:
	return StringName("%s_%d" % [kind, j])


func _place(at: Vector2, j: int) -> Vector2:
	return at + Vector2.from_angle(deg_to_rad(360.0 / DUMMIES * j + 10.0)) * DISTANCE
