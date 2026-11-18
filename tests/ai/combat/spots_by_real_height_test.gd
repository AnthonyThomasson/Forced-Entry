extends GameTest
## #194 rule 5 (docs/gaze-and-fire.md, docs/cover-and-stance.md A-rules): the spots an NPC weighs to
## fight from are classified by real heights. A spot behind a coffee table (18 px) has a clear shot
## (a standing muzzle, 65 px, is over it) and no cover (the table does not hide a ducked head); a
## spot behind a sofa's back (38 px) has both (it ducks behind it and rises over it to fire); a
## spot behind a wardrobe has cover and no shot (nothing it can fire over). The ring is the one
## `AgentTactics.combat_spots` samples round the NPC (96 px, 12 points), the spot under test is its
## east point and the piece stands just past it, the target 400 px beyond.

const AgentTactics := preload("res://scenes/ai/perception/agent_tactics.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const LANES := [
	[&"coffee_table", true, false],
	[&"sofa", true, true],
	[&"wardrobe", false, true],
]
const NPC_X := 300.0
const RADIUS := 96.0
const LANE_Y := 100.0
const LANE_GAP := 160.0


func describe() -> Dictionary:
	return {
		"name": "Fire and cover spots follow real heights",
		"description": "A spot behind a coffee table has a clear shot and no cover, behind a sofa "
			+ "both, behind a wardrobe cover and no shot.",
		"tags": ["ai", "combat", "cover", "heights", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, LANE_Y + LANE_GAP * LANES.size()))
	s.switch(&"nav.rebake", false)
	for i in LANES.size():
		var key := String(LANES[i][0])
		var def := WorldGen.object_definition(key).duplicate()
		if key == "sofa":
			def["size"] = Vector2(50, 120)
		def["anchored"] = true
		s.object(StringName("piece_%d" % i), def, Vector2(NPC_X + RADIUS + 50.0, _lane_y(i)),
				{ "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.frames(3)
	var tactics := AgentTactics.new()
	tactics.vision = AgentVision.new()
	tactics.combat_ring_count = 12
	var space := t.world.get_world_2d().direct_space_state
	for i in LANES.size():
		var name: StringName = LANES[i][0]
		var spot := Vector2(NPC_X + RADIUS, _lane_y(i))
		var spots := tactics.combat_spots(
			space,
			Vector2(NPC_X, _lane_y(i)),
			{ "pos": Vector2(NPC_X + 400.0, _lane_y(i)) },
			[],
			RADIUS,
		)
		t.expect_eq(
			_has(spots["fire"], spot), LANES[i][1],
			"the spot behind the %s %s a clear shot" % [name, "has" if LANES[i][1] else "has no"],
		)
		t.expect_eq(
			_has(spots["cover"], spot), LANES[i][2],
			"the spot behind the %s %s cover" % [name, "has" if LANES[i][2] else "has no"],
		)


func _has(points: Array, spot: Vector2) -> bool:
	for p: Vector2 in points:
		if p.distance_to(spot) < 1.0:
			return true
	return false


func _lane_y(i: int) -> float:
	return LANE_Y + LANE_GAP * i
