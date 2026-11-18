extends GameTest
## #194 rule 5 (docs/gaze-and-fire.md W2, docs/cover-and-stance.md P6): an NPC's line of fire is the
## real 3D line, so it fires over a piece that is low and holds its fire behind one that is not. A
## hostile ducked right behind a coffee table (18 px) shows its head, chest and hips over it to a
## defender 450 px off: the defender fights from where it stands and its rounds hit the hostile
## without a touch of the table (the 2D line it used to ask counted any piece as a wall and never
## fired). A hostile ducked right behind a sofa's back (38 px) shows it nothing: no round is
## wasted into the sofa. Server down, the defenders hold their ground (crouch, rise to fire) as
## they do in a match.

const SOFA_Y := 150.0
const TABLE_Y := 400.0
const NPC_X := 260.0
const PIECE_X := 650.0
const FOE_X := 710.0


func describe() -> Dictionary:
	return {
		"name": "An NPC fires over a low table and not into a sofa",
		"description": "A defender with a hostile ducked behind a coffee table shoots it over the "
			+ "table without hitting the table; with the hostile ducked behind a sofa's back it "
			+ "fires nothing into the sofa.",
		"tags": ["ai", "combat", "cover", "heights", "3d"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 560))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var sofa := WorldGen.object_definition("sofa").duplicate()
	sofa["size"] = Vector2(50, 120)
	sofa["anchored"] = true
	s.object(&"sofa", sofa, Vector2(PIECE_X, SOFA_Y), { "facing": Vector2.LEFT })
	var table := WorldGen.object_definition("coffee_table").duplicate()
	table["anchored"] = true
	s.object(&"table", table, Vector2(PIECE_X, TABLE_Y))
	s.actor(&"npc_sofa", &"defender", Vector2(NPC_X, SOFA_Y))
	s.actor(&"npc_table", &"defender", Vector2(NPC_X, TABLE_Y))
	var foe := { "faction": &"invader", "max_health": 100_000.0 }
	s.actor(&"foe_sofa", &"puppet", Vector2(FOE_X, SOFA_Y), foe)
	s.actor(&"foe_table", &"puppet", Vector2(FOE_X, TABLE_Y), foe)


func run(t: TestContext) -> void:
	for lane: StringName in [&"sofa", &"table"]:
		t.require(
			await t.until(
				func(): return t.actor(StringName("foe_%s" % lane)).movement.set_posture(&"crouch"),
				3.0,
			),
			"premise: the %s lane's hostile ducks behind its piece" % lane,
		)
	t.check(
		await t.until(func(): return _hits(t, t.actor(&"foe_table")) >= 3, 15.0),
		"the defender shoots the hostile ducked behind the coffee table (%d hits)"
		% _hits(t, t.actor(&"foe_table")),
	)
	await t.seconds(4.0)
	t.expect_eq(_hits(t, t.object(&"table")), 0, "and none of its rounds struck the table")
	t.expect_eq(_hits(t, t.object(&"sofa")), 0, "no round was wasted into the sofa")
	t.expect_eq(_hits(t, t.actor(&"foe_sofa")), 0, "and none reached the hostile behind it")


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()
