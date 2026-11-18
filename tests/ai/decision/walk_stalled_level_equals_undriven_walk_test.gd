extends GameTest
## A level the walk put back after a stall (`DecisionPlanner.stalled`) is the level it would have
## been had it run undriven: the same snapshot of one situation, walked once undriven (a group it
## reads is built whole on the spot) and once driven with each stall's group built by its steps,
## ends with the same levels, level for level (node, question, state, options, whether taken
## without asking, pick). What a stall restores (`DecisionWalk.restore`) is the whole of what the
## level changed.
##
## The set-up of `ai/decision/walk_stalls_on_an_unbuilt_group`: an invader with a frag and a stun
## outside the back door, two householders in the kitchen it sees through the doorway.

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
## Levels each walk may take at most: a walk that does not end is a failure of the test.
const MOST_FRAMES := 600
## The keys of a level the two walks must agree on (`ms`, how long Von took, is wall time).
const SAME := ["node", "question", "state", "offered", "auto", "pick"]


func describe() -> Dictionary:
	return {
		"name": "A walk put back after a stall equals the undriven walk",
		"description": "The same snapshot walked undriven and driven with stalls: the levels "
			+ "(node, question, state, options, pick) are equal, level for level.",
		"tags": ["ai", "decision", "grenade", "snapshot"],
		"timeout": 60.0,
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
	var undriven_snap := _prepared(perception, brain)
	var driven_snap := _prepared(perception, brain)
	if not t.require(
			undriven_snap["demand"].facts.get("grenade_ready", false)
				and driven_snap["demand"].facts.get("grenade_ready", false),
			"set-up: the search finds a throw in both snapshots",
	):
		return
	planner.driven = false
	planner.begin(undriven_snap, false)
	await t.until(func() -> bool: return not planner.is_pending(), 20.0)
	var undriven: Array = _levels(planner)
	planner.driven = true
	planner.begin(driven_snap, false)
	var stalls := await _walk(t, planner, driven_snap["demand"])
	var driven: Array = _levels(planner)
	t.check(stalls >= 1, "premise: the driven walk stalled (%d stalls)" % stalls)
	t.check(not undriven.is_empty(), "premise: the walk has levels (%d)" % undriven.size())
	t.expect_eq(driven.size(), undriven.size(), "the same number of levels")
	for i in mini(driven.size(), undriven.size()):
		t.expect_eq(driven[i], undriven[i], "level %d is the same" % i)


## A snapshot of the situation with the groups the job builds ahead of the walk built, and the
## grenade piece left out: the groups the walk reads are not built.
func _prepared(perception: Node, brain: Node) -> Dictionary:
	var snap: Dictionary = perception.sense(brain.get("goal"), "", 0)
	var demand: RefCounted = snap["demand"]
	_run_steps(demand.group_steps())
	_run_steps(demand.throw_search(1000))
	return snap


## The last walk's levels, each as the keys the two walks agree on.
func _levels(planner: Object) -> Array:
	var out: Array = []
	for level: Dictionary in planner.debug_state()["levels"]:
		var kept := {}
		for key: String in SAME:
			if level.has(key):
				kept[key] = level[key]
		out.append(kept)
	return out


## Walk the driven planner to its end, building each group a level stalls on; how many stalled.
func _walk(t: TestContext, planner: Object, demand: RefCounted) -> int:
	var stalls := 0
	var frames := 0
	while planner.is_pending() and frames < MOST_FRAMES:
		frames += 1
		if not planner.has_piece():
			await t.frames(1)
			continue
		planner.step()
		var need: Dictionary = planner.stalled()
		if need.is_empty():
			continue
		stalls += 1
		_run_steps(demand.steps_of(need["name"], need["id"]))
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
