extends GameTest
## The grenade piece builds ahead of the walk what the walk would otherwise build in one frame
## (`SnapshotDemand.grenade_steps`, G17 with the work-unit budget of `decision-prices.md`): once the
## throw search has found a throw, the throws at the hostile it found it at and at every other
## hostile given full analysis are built a unit a step (a read of one not built is 120 ms in one
## frame); the sources it went through before that are the empty group, with no planner call and
## equal to the group built whole. Once it has found
## none, every grenade group is the empty one the same way (the search and the groups agree,
## `ai/decision/throw_piece_matches_whole`).
##
## The Terrace house of `ai/decision/throw_piece_matches_whole`: an invader with a frag and a stun
## outside the back door and two householders in the kitchen it sees through the doorway.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")
const Kind := preload("res://scenes/ai/perception/snapshot/group_build.gd").Kind
const I_AT := Vector2(960, 190)
const H_JAMB := Vector2(660, 120)
const H_OTHER := Vector2(700, 160)
const FAR := Vector2(1500, 190)


func describe() -> Dictionary:
	return {
		"name": "Every hostile's throws are built before the walk, the sources passed are none",
		"description": "With a throw found, the grenade piece builds the throws at every "
			+ "hostile, the sources the search went through before the one it found are the empty "
			+ "group with no planner call, equal to the one built whole; with none, every "
			+ "grenade group is the empty one the same way.",
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
	inv.facing = (H_JAMB - I_AT).normalized()
	if not t.require(await _sees_two(t, brain), "set-up: the invader sees both householders"):
		return
	_found(t, perception, brain.get("goal"))
	inv.global_position = FAR
	await t.frames(3)
	_none(t, perception, brain.get("goal"))


## A throw exists: the search, then the grenade piece's steps, leave the throws at every hostile
## built; the sources it went through before are none, as the whole build says.
func _found(t: TestContext, perception: Node, goal: String) -> void:
	var whole: RefCounted = perception.sense(goal, "", 0)["demand"]
	var demand: RefCounted = perception.sense(goal, "", 0)["demand"]
	t.check(demand.targets.size() >= 2, "found: two hostiles are given full analysis")
	_search(demand)
	if not t.require(demand.facts.get("grenade_ready", false), "found: the search finds a throw"):
		return
	var steps: RefCounted = demand.grenade_steps()
	t.check(steps != null, "found: the grenade piece has throws to build")
	var guard := 0
	while steps != null and steps.next_kind() != Kind.DONE and guard < 500:
		steps.step()
		guard += 1
	var memo: Dictionary = demand.throws.memo_of(demand.ctx)
	var passed: Array = memo["passed"]
	var plans := GrenadeArc.plans
	for id in demand.targets:
		t.check(
			demand.holds("grenade_throws", id),
			"found: the throws at hostile %d are built before the walk" % id,
		)
		if id in passed:
			t.expect_eq(
				demand.target_group("grenade_throws", id), whole.target_group("grenade_throws", id),
				"found: the throws at hostile %d, passed by the search, are the whole build's" % id,
			)
	t.expect_eq(
		GrenadeArc.plans,
		plans,
		"found: reading the groups built asks the arc planner nothing",
	)


## No throw exists: every group is the empty one, no plan asked, equal to the whole build's.
func _none(t: TestContext, perception: Node, goal: String) -> void:
	var whole: RefCounted = perception.sense(goal, "", 0)["demand"]
	var want := {}
	for id in whole.targets:
		want[id] = whole.target_group("grenade_throws", id)
	var shots_want: Dictionary = whole.group("grenade_throws")
	var demand: RefCounted = perception.sense(goal, "", 0)["demand"]
	_search(demand)
	if not t.require(demand.facts.get("grenade_ready", true) == false, "none: no throw exists"):
		return
	t.check(demand.grenade_steps() == null, "none: the grenade piece has nothing to build")
	var plans := GrenadeArc.plans
	for id in demand.targets:
		t.expect_eq(
			demand.target_group("grenade_throws", id), want[id],
			"none: the throws at hostile %d are the whole build's" % id,
		)
	t.expect_eq(demand.group("grenade_throws"), shots_want, "none: the shots' throws too")
	t.expect_eq(GrenadeArc.plans, plans, "none: reading them asks the arc planner nothing")


func _search(demand: RefCounted) -> void:
	var search: RefCounted = demand.throw_search(1000)
	var guard := 0
	while search != null and search.next_kind() != ThrowSearch.Kind.DONE and guard < 500:
		search.step()
		guard += 1


func _sees_two(t: TestContext, brain: Node) -> bool:
	return await t.until(
		func() -> bool:
			return (brain.debug_state().get("contacts", []) as Array).filter(
				func(c): return c.get("hostile", false)
			).size() >= 2,
		3.0,
	)
