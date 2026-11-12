extends GameTest
## A decision the frame's pool has no unit for is not lost: two invaders that see a trespasser on
## their first frame both want to decide at once, one unit a frame lets one claim, and the other
## keeps its wish (`forced`, and why it was forced, with its decide timer run out) and claims on the
## next frame, as the decision for the reason that forced it, not as a cadence one.

const TARGET := Vector2(900, 60)


func describe() -> Dictionary:
	return {
		"name": "A decision the pool refused keeps its wish",
		"description": "Two invaders see a hostile at once; one claims the frame's unit, the "
			+ "other stays forced with its reason and claims on the next frame.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1800, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.set_static(DecisionBudget, "per_frame", 1)
	for i in 2:
		var at := Vector2(150 + i * 200, 300)
		s.actor(
			StringName("inv%d" % i),
			&"invader",
			at,
			{ "movement:speed": 0.0, "facing": (TARGET - at).normalized() },
		)
	s.actor(&"tgt", &"puppet", TARGET, { "faction": &"household", "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var brains: Array = [
		t.controller(&"inv0", &"debug_state"), t.controller(&"inv1", &"debug_state"),
	]
	var waiting := -1
	var reason := ""
	for brain in brains:
		brain.get("_cadence").force("probe")  # both want a forced decision on the same frame
	for frame in 40:
		await t.frames(1)
		var decided: Array = brains.map(func(b): return int(b.debug_state()["decisions"]))
		if waiting < 0 and decided.count(0) == 1:
			# One has claimed the frame's unit; the other, refused, is still wishing.
			waiting = decided.find(0)
			var state: Dictionary = brains[waiting].debug_state()
			t.check(bool(state["forced"]), "the refused NPC keeps its wish (forced)")
			t.check(
				float(state["decide_in"]) <= 0.0,
				"and its decide timer stays run out (%s)" % state["decide_in"],
			)
		elif waiting >= 0 and decided[waiting] > 0:
			reason = String(brains[waiting].debug_state()["decision_reason"])
			break
	if not t.require(waiting >= 0, "the pool refused one of the two on a frame"):
		return
	t.check(reason != "", "the refused NPC claimed on a later frame")
	t.check(reason == "probe", "as the decision for the reason that forced it (\"%s\")" % reason)
