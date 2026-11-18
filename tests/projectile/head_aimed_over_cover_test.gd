extends GameTest
## D8 and O2, O3 (docs/cover-and-stance.md, docs/outfits.md): a shot aimed at a body's head over low
## cover strikes the head, and where a round meets a body is the hit zone, by the height it strikes
## at. Two shooters fire a pistol round at a standing body behind a table (30 px): one aimed at its
## head (70 px up), one at its torso (50). Both clear the table; the head shot costs twice the
## health (O3: head x2, torso x1).

const LANES := { &"head": [150.0, 70.0], &"torso": [350.0, 50.0] }
const SHOOT_X := 120.0
const TABLE_X := 400.0
const BODY_X := 480.0


func describe() -> Dictionary:
	return {
		"name": "A head aimed over cover is a head shot",
		"description": "Pistol rounds aimed at a standing body's head and at its torso, over a "
			+ "table: both clear the table, the head shot takes twice the health of the torso "
			+ "one.",
		"tags": ["projectile", "cover", "aim", "zone", "outfit"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	for lane: StringName in LANES:
		var y: float = LANES[lane][0]
		s.actor(StringName("shooter_%s" % lane), &"puppet", Vector2(SHOOT_X, y),
				{ "start_slot": 3 })
		s.object(StringName("table_%s" % lane), "table", Vector2(TABLE_X, y))
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(BODY_X, y),
				{ "max_health": 10_000.0, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).aim_at(
				t.actor(StringName("body_%s" % lane)), LANES[lane][1])
	await t.seconds(0.5)
	for lane: StringName in LANES:
		t.puppet(StringName("shooter_%s" % lane)).shoot()
	await t.seconds(1.0)

	for lane: StringName in LANES:
		t.expect_eq(
			_hits(t, t.object(&"table_%s" % lane)),
			0,
			"the %s shot clears the table" % lane,
		)
		t.expect_eq(
			_hits(t, t.actor(&"body_%s" % lane)),
			1,
			"and strikes the %s lane's body" % lane,
		)
	var head := _lost(t, &"head")
	var torso := _lost(t, &"torso")
	t.check(torso > 0.0, "the torso shot wounds (%.1f)" % torso)
	t.expect_near(head / maxf(torso, 0.001), 2.0, 0.15,
			"the head shot costs twice the torso shot (%.1f against %.1f)" % [head, torso])


func _lost(t: TestContext, lane: StringName) -> float:
	var body := t.actor(StringName("body_%s" % lane))
	return body.max_health - body.health


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
