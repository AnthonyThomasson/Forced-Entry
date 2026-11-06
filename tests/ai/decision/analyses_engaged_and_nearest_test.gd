extends GameTest
## A decision gives full combat analysis to at most two hostiles: the engaged one always takes a
## slot, even when farthest, and the nearest other takes the second. The third stays in the shared
## contacts and odds facts but has no per-target option groups or sections.
##
## Scripted Von isolates snapshot construction. The nearest initial hostile is engaged, then steps
## beyond both others before the next decision, so engaged-first selection cannot pass by accident.

const NPC := Vector2(150, 250)
const ENGAGED_START := Vector2(300, 100)
const ENGAGED_FAR := Vector2(750, 100)
const NEAREST := Vector2(400, 100)
const OTHER := Vector2(650, 100)


func describe() -> Dictionary:
	return {
		"name": "Combat analyses cover the engaged hostile and the nearest other",
		"description": "With three hostiles known and the engaged one farthest, only it and the "
			+ "nearest other receive per-target groups; all three remain in contacts and facts.",
		"tags": ["ai", "decision", "combat", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.callouts", false)
	s.actor(&"d", &"defender", NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	s.set_props(
		&"d",
		"GoalController",
		{
			"tuning:decision:decide_interval": 0.4,
			"tuning:decision:tactic_interval": 0.4,
			"tuning:decision:max_commit_time": 0.4,
		},
	)
	for pair in [
			[&"engaged", ENGAGED_START], [&"nearest", NEAREST], [&"other", OTHER],
	]:
		s.actor(pair[0], &"puppet", pair[1], { "faction": &"invader", "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	if not t.require(
			await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 3.0),
			"the nearest initial hostile was engaged",
		):
		return
	var engaged := t.actor(&"engaged")
	if not t.require(int(brain.debug_state().get("engage_id", 0)) == engaged.get_instance_id(),
			"set-up: the hostile that moves farthest is the engaged one"):
		return
	engaged.global_position = ENGAGED_FAR
	var before := int(brain.debug_state().get("decisions", 0))
	if not t.require(
			await t.until(func(): return (int(brain.debug_state().get("decisions", 0)) > before
				and not bool(brain.debug_state().get("decision", {}).get("pending", false))), 3.0),
			"a second snapshot was built with the engaged hostile farthest",
		):
		return
	var state: Dictionary = brain.debug_state()
	var expected: Array = [engaged.get_instance_id(), t.actor(&"nearest").get_instance_id()]
	expected.sort()
	var analysed: Array = state.get("analysed_targets", [])
	analysed.sort()
	t.check(
		analysed == expected,
		"per-target groups cover the engaged and nearest other only (got %s, want %s)"
			% [analysed, expected],
	)
	t.check((state.get("contacts", []) as Array).size() == 3, "all three hostiles stay in contacts")
	t.check(
		str(state.get("sections", {}).get("odds", "")).contains("Known hostiles: 3"),
		"the shared odds fact still counts all three hostiles",
	)
