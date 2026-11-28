extends GameTest
## G7, cover (#194 D10: the blast's line is the real 3D line from the burst to the body): besides
## walls, a piece of furniture on the line from the blast to a character blocks it when the line
## cannot clear it: it ends at a point of the body (head, chest, hips) lower than the piece's top
## would let it pass. A body hunched behind a couch (its head top at 36 px, the couch's back 38) is
## shielded whatever the distance, and a standing one right behind it is not: the blast comes over
## the back to its head. Two dummies stand just behind a row of three couches, one crouched and
## one standing; a frag goes off on the other side, far enough from the couches for the line to
## rise over their backs by the standing dummy.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const GrenadeSpec := preload("res://tests/_ai/grenade_spec_probe.gd")
const FROM := Vector2(100, 340)
const AIM := Vector2(500, 340)
## the couches, 140 px south of the aim point (three across, 360 px wide; the back at their
## north edge, y 455, 115 px from the burst)
const ROW_Y := 480.0
## the dummies, just behind them, about 190 px from the aim point
const BEHIND_Y := 530.0
## Slack on the damage formula: the body has a radius and the blast point is the grenade's rest
## point, not the aim point.
const SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "A crouched character behind a couch is shielded from a frag blast, a standing one "
			+ "right behind it is not",
		"description": "A row of couches 115 px from where a frag goes off; behind it a crouched "
			+ "dummy takes no blast hit and a standing one at the same distance takes the blast "
			+ "(the line clears the back to the standing head, not to the crouched one).",
		"tags": ["grenade", "frag", "blast", "cover", "posture"],
		"timeout": 16.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	s.switch(&"nav.rebake", false)
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(AIM.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"thrower", &"puppet", FROM, { "max_health": 100_000.0 })
	s.actor(&"crouched", &"puppet", Vector2(AIM.x - 60.0, BEHIND_Y), { "max_health": 100_000.0 })
	s.actor(&"standing", &"puppet", Vector2(AIM.x + 60.0, BEHIND_Y), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	var crouched := t.actor(&"crouched")
	var standing := t.actor(&"standing")
	Probe.arm(thrower, 0, 1)
	if not t.require(
			Probe.count(thrower, Probe.FRAG) == 1,
			"the thrower carries a frag grenade (Character.inventory.item_count(8) = %d)"
				% Probe.count(thrower, Probe.FRAG),
	):
		return
	t.puppet(&"crouched").set_posture(&"crouch")
	t.puppet(&"standing").set_posture(&"stand")
	await t.seconds(0.6)
	t.require(
		crouched.movement.posture() == &"crouch" and standing.movement.posture() == &"stand",
		"set-up: one dummy crouches and the other stands",
	)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, AIM)
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	var blast: Vector2 = Probe.booms(t, &"frag")[0]["data"]["position"]
	await t.frames(3)
	var d_standing: float = standing.global_position.distance_to(blast)
	var d_crouched: float = crouched.global_position.distance_to(blast)
	t.require(
		blast.y < ROW_Y - 100.0
			and d_crouched < Probe.BLAST_RADIUS
			and d_standing < Probe.BLAST_RADIUS,
		("set-up: the frag went off on the near side of the couches (%s), both dummies inside the "
				+ "blast radius (%.0f and %.0f px)") % [str(blast.round()), d_crouched, d_standing],
	)
	t.check(
		GrenadeAi.shielded(t, blast, crouched) and not GrenadeAi.shielded(t, blast, standing),
		"the couches shield the crouched dummy's body and not the standing one's (the line clears "
			+ "the 38 px back to a head at 69 and not to one at 32)",
	)

	_check_hits(t, blast)


## The blast hits: the standing dummy takes the usual damage, the crouched one behind the same
## couches none.
func _check_hits(t: TestContext, blast: Vector2) -> void:
	var crouched := t.actor(&"crouched")
	var standing := t.actor(&"standing")
	var d_standing: float = standing.global_position.distance_to(blast)
	var d_crouched: float = crouched.global_position.distance_to(blast)
	var hits := Probe.blast_hits(t, standing)
	if t.check(
			not hits.is_empty(),
			"the standing dummy %.0f px from the blast takes a blast hit" % d_standing,
	):
		var want := GrenadeSpec.blast_damage(d_standing)
		t.check(
			absf(float(hits[0]["data"]["damage"]) - want) <= SLACK,
			"of the usual damage (%.1f, expected about %.1f)" % [hits[0]["data"]["damage"], want],
		)
	t.check(
		Probe.blast_hits(t, crouched).is_empty(),
		"the crouched dummy %.0f px from the blast, behind the same couches, takes none"
			% d_crouched,
	)
