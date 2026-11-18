extends GameTest
## G7 (#194 D10): the blast is shielded by the real 3D line from the burst to the body, so a low
## piece casts a shadow: a standing body far enough behind a couch is in it, the line from the
## burst (on the floor) rising too little to clear the couch's 38 px back before it reaches the
## body. (The old rule compared the couch's 45 to the standing body's 60 and shielded none standing
## at any distance.) Couches 55 px from the burst: a standing dummy 125 px behind them is in their
## shadow (no blast hit), a crouched one close behind them is shielded, and a standing one in the
## open at the same distance from the burst takes the blast.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const FROM := Vector2(100, 400)
const AIM := Vector2(500, 400)
## the couches, 80 px south of the aim point (their back edge at y 455, their front at 505)
const ROW_Y := 480.0


func describe() -> Dictionary:
	return {
		"name": "A low couch casts a shadow from a frag blast on a standing body far behind it",
		"description": "A row of couches 55 px from where a frag goes off: a standing dummy far "
			+ "behind them is in their shadow and takes no blast, a crouched one close behind "
			+ "them is shielded, and a standing one in the open takes the blast.",
		"tags": ["grenade", "frag", "blast", "cover", "shadow", "3d"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	s.switch(&"nav.rebake", false)
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(AIM.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })
	s.actor(&"open", &"puppet", Vector2(AIM.x + 180.0, 430.0), { "max_health": 100_000.0 })
	s.actor(&"ducked", &"puppet", Vector2(AIM.x + 90.0, 530.0), { "max_health": 100_000.0 })
	s.actor(&"far", &"puppet", Vector2(AIM.x, 580.0), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	Probe.arm(thrower, 0, 1)
	if not t.require(Probe.count(thrower, Probe.FRAG) == 1, "the thrower carries a frag"):
		return
	t.puppet(&"ducked").set_posture(&"crouch")
	await t.seconds(0.6)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.frames(3)
	var open := t.actor(&"open")
	var far := t.actor(&"far")
	var ducked := t.actor(&"ducked")
	var gap: float = far.global_position.distance_to(blast)
	t.require(
		blast.y < ROW_Y - 60.0 and gap < Probe.BLAST_RADIUS - 30.0,
		(
			"set-up: the frag went off on the near side of the couches (%s), the far dummy "
			+ "inside the radius (%.0f px)"
		) % [str(blast.round()), gap],
	)
	t.check(
		GrenadeAi.shielded(t, blast, far) and GrenadeAi.shielded(t, blast, ducked)
			and not GrenadeAi.shielded(t, blast, open),
		"the 3D lines: the far standing dummy and the crouched one are shielded, the one in "
			+ "the open is not",
	)
	t.check(not Probe.blast_hits(t, open).is_empty(), "the standing dummy in the open is hit")
	t.check(
		Probe.blast_hits(t, far).is_empty(),
		"the standing dummy far behind the couches is in their shadow and takes no blast",
	)
	t.check(Probe.blast_hits(t, ducked).is_empty(), "the crouched dummy takes none either")
