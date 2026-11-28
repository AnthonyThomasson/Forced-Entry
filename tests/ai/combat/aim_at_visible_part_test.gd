extends GameTest
## #194 D8, D9 (docs/gaze-and-fire.md W2): an NPC fires where it sees. Its line of fire is the 3D
## line from its muzzle to the middle of the part of the target it sees (`SightRay.visible_centre`)
## and its round is aimed at that same point: the head of a ducked body that shows only its head
## over a kitchen counter (38 px), the middle of the torso of a standing body in the open. Two
## defenders stand and fight (server down; `ai.posture` off keeps them on their feet, the premise:
## the standing muzzle is what clears the counter): the round passes over the counter to the head
## (a head costs twice a torso, `docs/outfits.md` O3) and the counter is never struck.

const OPEN_Y := 120.0
const COUNTER_Y := 320.0
const NPC_X := 200.0
const COUNTER_X := 500.0
## The ducked target 110 px past the counter's far face (550): its head shows, its chest does not
## (`tests/general/sight_visible_parts_test.gd`).
const BEHIND_X := 660.0
## The head's middle of a ducked body (px) and a standing torso's (`BodyHeights`).
const HEAD := 32.2
const TORSO := 51.0


func describe() -> Dictionary:
	return {
		"name": "An NPC aims at the part of the target it sees",
		"description": "A defender fires over a counter at the head of a ducked body that shows "
			+ "only its head, and at the torso of a standing body in the open; the head shot "
			+ "costs twice the torso one and no round strikes the counter.",
		"tags": ["ai", "combat", "aim", "heights", "3d"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 460))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"ai.posture", false)
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsPenetrationConfig, &"min_speed", 1.0e9)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, &"guns", straight)
	s.object(&"counter", "kitchen_counter", Vector2(COUNTER_X, COUNTER_Y))
	s.actor(&"npc_head", &"defender", Vector2(NPC_X, COUNTER_Y))
	s.actor(&"npc_torso", &"defender", Vector2(NPC_X, OPEN_Y))
	var foe := { "faction": &"invader", "max_health": 100_000.0 }
	s.actor(&"foe_head", &"puppet", Vector2(BEHIND_X, COUNTER_Y), foe)
	s.actor(&"foe_torso", &"puppet", Vector2(BEHIND_X, OPEN_Y), foe)


func run(t: TestContext) -> void:
	var foe_head := t.actor(&"foe_head")
	t.require(
		await t.until(func(): return foe_head.movement.set_posture(&"crouch"), 3.0),
		"premise: the target ducks behind the counter",
	)
	var aimed := { &"head": [], &"torso": [] }
	for _frame in 60 * 25:
		await t.frames(1)
		for lane: StringName in aimed:
			var npc := t.actor(StringName("npc_%s" % lane))
			if npc.weapon.aim_height() > 0.0 and _hits(t, lane) > aimed[lane].size():
				aimed[lane].append(npc.weapon.aim_height())
		if _hits(t, &"head") >= 2 and _hits(t, &"torso") >= 2:
			break
	for lane: StringName in aimed:
		t.check(
			_hits(t, lane) >= 2,
			"the %s lane's defender hit its target (%d hits)" % [lane, _hits(t, lane)],
		)
		t.check(
			t.actor(StringName("npc_%s" % lane)).movement.posture() == &"stand",
			"the %s lane's defender stood to fight" % lane,
		)
	t.expect_eq(_hits(t, &"counter"), 0, "no round was wasted into the counter")
	t.check(not aimed[&"head"].is_empty(), "the head lane's shots were measured")
	t.check(not aimed[&"torso"].is_empty(), "the torso lane's shots were measured")
	if aimed[&"head"].is_empty() or aimed[&"torso"].is_empty():
		return
	t.expect_near(aimed[&"head"][0], HEAD, 1.0, "it aims at the head that shows over the counter")
	t.expect_near(aimed[&"torso"][0], TORSO, 3.0, "and at the middle of a body in full view")
	var head_cost := _lost(t, &"head") / maxf(_hits(t, &"head"), 1)
	var torso_cost := _lost(t, &"torso") / maxf(_hits(t, &"torso"), 1)
	t.expect_near(
		head_cost / maxf(torso_cost, 0.001), 2.0, 0.2,
		"a head shot costs twice a torso one (%.1f against %.1f)" % [head_cost, torso_cost],
	)


## The rounds that struck the lane's target (`head`, `torso`) or the counter.
func _hits(t: TestContext, lane: StringName) -> int:
	var victim: Node = t.object(&"counter")
	if lane != &"counter":
		victim = t.actor(StringName("foe_%s" % lane))
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()


func _lost(t: TestContext, lane: StringName) -> float:
	var body := t.actor(StringName("foe_%s" % lane))
	return body.max_health - body.health
