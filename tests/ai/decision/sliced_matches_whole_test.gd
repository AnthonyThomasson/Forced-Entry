extends GameTest
## A decision spread over frames by the shipped prices (`DecisionBudget`: a start, each hostile, the
## finish, each throw step, one unit or more apiece, a pool of a few units a frame) decides what the
## same decision run whole in one frame does, on a still world (#195): the same levels (node,
## question, state text, options, pick) and the same path adopted, the same facts and sections in
## the snapshot, and the same answer to the throw search. Only when it lands differs.
##
## The Terrace house: an invader with a frag outside the back door that sees a householder through
## the doorway off its axis, so the decision builds a snapshot with a hostile analysed, searches
## for a throw over several steps and walks COMBAT and its levels. Held still (speed 0), the
## householder never moves, scripted Von (the scene's own: left, right, rear), no allies.

const Fakes := preload("res://tests/_ai/job_fakes.gd")
const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const NPC_POS := Vector2(960, 190)
const TARGET_POS := Vector2(660, 120)
## A second householder, in the doorway's view too: two hostiles analysed make the build's pieces
## dearer than a frame's pool, whatever the throw search finds.
const TARGET2_POS := Vector2(720, 170)


func describe() -> Dictionary:
	return {
		"name": "A sliced decision decides what a whole one does",
		"description": "On a still world the shipped prices (a decision over several frames) and "
			+ "the whole prices (one frame) give the same walk, path, snapshot facts and "
			+ "sections.",
		"tags": ["ai", "decision", "snapshot", "grenade", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Flank.rules(s)
	s.switch(&"ai.callouts", false)
	# Registered so the harness puts the pool and the prices back after the test sets them whole.
	for name: String in Fakes.PRICES:
		s.set_static(DecisionBudget, name, Fakes.prices()[name])
	# No cadence decision between the two forced ones: the one under test is the one read.
	var quiet := {
		"tuning:decision:max_commit_time": 600.0,
		"tuning:decision:tactic_interval": 600.0,
		"tuning:decision:decide_interval": 600.0,
	}
	Flank.npc(s, &"npc", NPC_POS, quiet, { "look_at": TARGET_POS })
	GrenadeAi.hostile(s, &"target", TARGET_POS, Maps.DOOR_BACK)
	GrenadeAi.hostile(s, &"target2", TARGET2_POS, Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"npc"), 1, 1)  # it carries a frag: there is a throw to search for
	var brain := t.controller(&"npc", &"current_act")
	var cadence: RefCounted = brain.get("_cadence")
	if not await Flank.settle(t, brain):
		return
	var sliced := await _decide(t, brain, cadence)
	Fakes.whole_prices()  # the pool and the prices a decision that runs whole in a frame has
	var whole := await _decide(t, brain, cadence)
	if not t.require(
			not sliced.is_empty() and not whole.is_empty(), "set-up: both decisions landed"
	):
		return
	t.check(
		int(sliced["frames"]) >= 2,
		"premise: the shipped prices spread the decision over frames (%d, %d analysed)"
			% [sliced["frames"], sliced["analysed"]],
	)
	t.expect_eq(whole["frames"], 1, "premise: the whole prices land it in the frame it began")
	t.check(
		(sliced["levels"] as Array).size() >= 2,
		"premise: the walk went through levels (%d)" % (sliced["levels"] as Array).size(),
	)
	t.expect_eq(
		sliced["levels"],
		whole["levels"],
		"the same levels: question, state, options, pick",
	)
	t.expect_eq(sliced["act"], whole["act"], "the same path adopted")
	t.expect_eq(sliced["facts"], whole["facts"], "the same facts in the snapshot")
	t.expect_eq(sliced["sections"], whole["sections"], "the same sections in the snapshot")


## `text` with the engagement phase of the "Current activity" line, its parenthetical, left out
## ("(moving into position, for 0s)" or "(in position, ducking behind cover, for 0s)"): where the
## NPC is in carrying out its last choice moves on between the two decisions, a thing no decision
## decides, whereas the activity itself ("COMBAT - target2 - ENGAGE - where you stand") stays in.
func _without_phase(text: String) -> String:
	var phase := RegEx.create_from_string("(Current activity:[^\\n(]*)\\([^)]*\\)")
	return phase.sub(text, "$1(phase)", true)


## One decision, forced now and read when it has landed: `{ frames, levels, act, facts, sections }`,
## or {} when it did not land. `frames` counts the physics frames from its claim to its landing.
func _decide(t: TestContext, brain: Node, cadence: RefCounted) -> Dictionary:
	var before := int(brain.debug_state()["decisions"])
	cadence.force("probe")
	var claimed := -1
	var landed := -1
	for frame in 120:
		await t.frames(1)
		var now := Engine.get_physics_frames()
		if claimed < 0 and int(brain.debug_state()["decisions"]) > before:
			claimed = now
		if claimed >= 0 and not bool(brain.debug_state()["decision"]["pending"]):
			landed = now
			break
	if claimed < 0 or landed < 0:
		return {}
	var levels: Array = []
	for level: Dictionary in brain.debug_state()["decision"]["levels"]:
		levels.append({
			"node": level["node"],
			"question": level.get("question", ""),
			"state": _without_phase(String(level.get("state", ""))),
			"offered": level["offered"],
			"pick": level.get("pick", ""),
			"auto": level["auto"],
		})
	return {
		"frames": landed - claimed + 1,
		"analysed": cadence.last_analysed.size(),
		"levels": levels,
		"act": String(brain.current_act()),
		"facts": cadence.last_facts.duplicate(),
		"sections": _sections_without_phase(cadence.last_sections),
	}


## The snapshot's sections with the activity's phase left out (`_without_phase`).
func _sections_without_phase(sections: Dictionary) -> Dictionary:
	var out := sections.duplicate()
	out["current"] = _without_phase(String(out.get("current", "")))
	return out
