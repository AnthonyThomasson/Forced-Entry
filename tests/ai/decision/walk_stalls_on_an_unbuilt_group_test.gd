extends GameTest
## A level of the walk that reads a hostile's throws not built yet does not build them: it stalls
## (`DecisionPlanner.stalled`, a `{ name, id }`), the decision job builds that group a priced step
## at a time and the level runs again. A read that built the group whole was one frame of 120 ms in
## a grenade match (`perf/grenade_match_stress`), and a step of the walk asks the arc planner
## nothing.
##
## The Terrace house of `ai/decision/throw_groups_built_before_the_walk`: an invader with a frag and
## a stun outside the back door and two householders in the kitchen it sees through the doorway;
## the throw search has run, the grenade piece has not: the groups the walk reads are not built.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")
const GroupBuild := preload("res://scenes/ai/perception/snapshot/group_build.gd")
const I_AT := Vector2(960, 190)
const H_JAMB := Vector2(660, 120)
const H_OTHER := Vector2(700, 160)
## Levels the test walks at most, and the stalls they may make: a group a time.
const MOST_STEPS := 12
const MOST_STALLS := 6


func describe() -> Dictionary:
	return {
		"name": "A walk read of an unbuilt group stalls and never builds it whole",
		"description": "A level that reads a hostile's throws not built yet stalls with the "
			+ "group it needs; built by its steps the level runs again, and no step of the walk "
			+ "asks the arc planner.",
		"tags": ["ai", "decision", "grenade", "snapshot", "perf"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"i", &"invader", I_AT, { "movement:speed": 0.0, "facing": Vector2.LEFT })
	GrenadeAi.hostile(s, &"h", H_JAMB, Maps.DOOR_BACK)
	GrenadeAi.hostile(s, &"h2", H_OTHER, Maps.DOOR_BACK)
	s.set_props(
		&"i",
		"GoalController",
		{
			"tuning:decision:decide_interval": 1000.0,
			"tuning:decision:tactic_interval": 1000.0,
			"tuning:decision:max_commit_time": 1000.0,
		},
	)


func run(t: TestContext) -> void:
	var inv := t.actor(&"i")
	Probe.arm(inv, 1, 1)
	await t.frames(3)
	var brain := t.controller(&"i", &"debug_state")
	var perception: Node = brain.get("_perception")
	var planner: Object = (brain.get("_job") as RefCounted).planner
	inv.facing = (H_JAMB - I_AT).normalized()
	var seen := await t.until(
		func() -> bool:
			return (brain.debug_state().get("contacts", []) as Array).filter(
				func(c): return c.get("hostile", false)
			).size() >= 2,
		3.0,
	)
	if not t.require(seen, "set-up: the invader sees both householders"):
		return
	var snap: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var demand: RefCounted = snap["demand"]
	_run_steps(demand.group_steps())
	_run_steps(demand.throw_search(1000))
	if not t.require(demand.facts.get("grenade_ready", false), "set-up: the search finds a throw"):
		return
	# The grenade piece is left out: the root's exposure reads the throws at the nearest hostile.
	planner.begin(snap, false)
	var stalls := await _walk(t, planner, demand)
	planner.cancel()
	t.check(stalls >= 1, "premise: the walk reads a group not built (%d stalls)" % stalls)
	t.check(stalls <= MOST_STALLS, "a group a stall, never more than the hostiles' (%d)" % stalls)


## Step the walk's levels (Von answers between them), building each group a level stalls on; how
## many levels stalled.
func _walk(t: TestContext, planner: Object, demand: RefCounted) -> int:
	var stalls := 0
	var steps := 0
	while planner.is_pending() and steps < MOST_STEPS:
		if not planner.has_piece():
			await t.frames(1)  # Von is being asked: its answer makes the next level ready
			continue
		steps += 1
		var plans := GrenadeArc.plans
		planner.step()
		t.expect_eq(GrenadeArc.plans, plans, "a step of the walk asks the arc planner nothing")
		var need: Dictionary = planner.stalled()
		if need.is_empty():
			continue
		stalls += 1
		t.check(
			not demand.holds(need["name"], need["id"]),
			"it stalls on a group not built (%s of %d)" % [need["name"], need["id"]],
		)
		_run_steps(demand.steps_of(need["name"], need["id"]))
		t.check(demand.holds(need["name"], need["id"]), "its steps build the group it needs")
	return stalls


## Run every step of `steps` (a `GroupSteps` or a `ThrowSearch`; null: none to run).
func _run_steps(steps: RefCounted) -> void:
	var guard := 0
	while steps != null and guard < 500:
		var kind: int = steps.next_kind()
		if kind == GroupBuild.Kind.DONE or kind == ThrowSearch.Kind.DONE:
			return
		steps.step()
		guard += 1
