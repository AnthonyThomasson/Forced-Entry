extends GameTest
## A heard lead's route and snapped point are remembered for the belief window (`tuning.decision.
## belief_redecide_interval`), keyed on the two ends of the walk and the state of the doors, and
## forgotten when a re-baked map is swapped in (#192 rule 25). The lead group built inside the
## window equals the one built with no window at all (the plain computation), a repeat inside the
## window computes no walk, and a door turned or a re-bake swapped in between drops what was
## remembered.
##
## The Terrace house with a chair in the living room (moved, then a re-bake, in the last step): an
## invader stands still in the hall and hears gunfire in the kitchen. The walks the doorway views
## compute (`AgentDoorViews.walk_queries`) show a hit or a recompute.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_AT := Vector2(420, 415)
const GUNFIRE_AT := Vector2(660, 190)
const CHAIR_AT := Vector2(260, 200)
## The back door's hinge on its jamb (the kitchen's east wall, the doorway 60 px wide).
const HINGE := Vector2(840, 166)
## A window long enough that a swing and a re-bake end inside it.
const WINDOW := 20.0


func describe() -> Dictionary:
	return {
		"name": "A heard lead's route memo matches the plain lead",
		"description": "Inside the belief window a heard lead's route and snap are remembered and "
			+ "the lead group equals the plain one; a door turned or a re-bake swapped in drops "
			+ "them.",
		"tags": ["ai", "perception", "investigate", "path"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false, {
		"name": "back_door", "material": "hollow", "style": "flush",
		"hinge": HINGE, "swing_into": Vector2.LEFT,
	})
	s.von_script([])
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"npc", &"invader", NPC_AT, { "movement:speed": 0.0 })
	s.object(&"chair", "chair", CHAIR_AT)
	s.set_props(
		&"npc",
		"GoalController",
		{
			"tuning:decision:decide_interval": 1000.0,
			"tuning:decision:tactic_interval": 1000.0,
			"tuning:decision:max_commit_time": 1000.0,
		},
	)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var brain := t.controller(&"npc", &"debug_state")
	var perception: Node = brain.get("_perception")
	var decision: Object = brain.tuning.decision
	decision.belief_redecide_interval = WINDOW
	var views: RefCounted = perception.views.views
	EventBus.post(
		&"hit",
		{
			"position": GUNFIRE_AT, "direction": Vector2.LEFT, "damage": 10.0,
			"attacker": null, "victim": null,
		},
	)
	await t.frames(3)
	var first := _leads(brain, perception, views)
	if not t.require(
			(first["leads"]["options"] as Array).size() > 0 and first["walks"] > 0,
			"set-up: the gunfire is a lead whose route is walked (%s)" % str(first),
	):
		return
	var again := _leads(brain, perception, views)
	t.expect_eq(again["leads"], first["leads"], "a repeat inside the window gives the same leads")
	t.expect_eq(again["walks"], 0, "a repeat inside the window walks no route again")
	decision.belief_redecide_interval = 0.0
	var plain := _leads(brain, perception, views)
	t.expect_eq(plain["leads"], first["leads"], "the leads equal the plain computation's")
	t.check(plain["walks"] > 0, "with no window the route is walked again (%d)" % plain["walks"])
	decision.belief_redecide_interval = WINDOW
	_leads(brain, perception, views)
	await _door_turn(t, brain, perception, views)
	await _rebake(t, brain, perception, views)


## A door turned inside the window drops what was remembered: the walk is made again, and the lead
## equals the plain one.
func _door_turn(t: TestContext, brain: Node, perception: Node, views: RefCounted) -> void:
	var door: Node = t.object(&"back_door")
	if not t.require(door != null, "set-up: the house has a door"):
		return
	door.turn_by(40.0, null)
	await t.seconds(1.5)
	var after := _leads(brain, perception, views)
	t.check(after["walks"] > 0, "a door turned inside the window drops the route memo")
	brain.tuning.decision.belief_redecide_interval = 0.0
	var plain := _leads(brain, perception, views)
	t.expect_eq(after["leads"], plain["leads"], "after the door turn the leads are the plain ones")
	brain.tuning.decision.belief_redecide_interval = WINDOW
	_leads(brain, perception, views)


## A re-bake swapped in inside the window drops what was remembered, and the lead equals the plain
## one over the new map.
func _rebake(t: TestContext, brain: Node, perception: Node, views: RefCounted) -> void:
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	var before := NavigationServer2D.map_get_iteration_id(map)
	t.object(&"chair").global_position = Vector2(100, 100)
	NavBuilder.rebake(region, t.world.house, t.rooms)
	if not t.require(
			await t.until(
				func(): return NavigationServer2D.map_get_iteration_id(map) != before, 3.0,
			),
			"set-up: the re-baked map is swapped in",
	):
		return
	var after := _leads(brain, perception, views)
	t.check(after["walks"] > 0, "a re-bake swapped in inside the window drops the route memo")
	brain.tuning.decision.belief_redecide_interval = 0.0
	var plain := _leads(brain, perception, views)
	t.expect_eq(after["leads"], plain["leads"], "after the re-bake the leads equal the plain ones")


## The lead group of a fresh snapshot, and how many walks building it computed:
## `{ leads, walks }`.
func _leads(brain: Node, perception: Node, views: RefCounted) -> Dictionary:
	var demand = perception.sense(brain.get("goal"), "", 0)["demand"]
	var before: int = views.walk_queries
	var leads: Dictionary = demand.group("leads")
	return { "leads": leads, "walks": views.walk_queries - before }
