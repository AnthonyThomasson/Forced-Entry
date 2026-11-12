extends GameTest
## A decision priced above the pool is spread over frames, piece by piece, and still lands: with
## every piece costing a unit and the pool one unit a frame (`DecisionBudget`), an invader that
## sees a trespasser claims its decision on one frame and Von is not asked its first question
## until the build's pieces and the order-refusal step have each had a frame of their own; the
## walk then goes on level by level (each level one more frame) and adopts a leaf, so a priced
## piece never stalls a job. The default prices run all of it in the claim frame
## (`decisions_spread_over_frames`).

## The pieces ahead of the first question: the build's finish, the order-refusal step and the
## first level at least, each on a frame after the claim's (the start runs on the claim's).
const PIECES_BEFORE_THE_ASK := 3
const TARGET := Vector2(700, 200)


func describe() -> Dictionary:
	return {
		"name": "A priced decision is spread over frames",
		"description": "With every piece of a decision costing the pool's one unit, Von is asked "
			+ "its first question at least three frames after the claim and the walk still "
			+ "lands its leaf.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.set_static(DecisionBudget, "per_frame", 1)
	s.set_static(DecisionBudget, "cost_hostile", 1)
	s.set_static(DecisionBudget, "cost_finish", 1)
	s.set_static(DecisionBudget, "cost_refusal", 1)
	s.set_static(DecisionBudget, "cost_level", 1)
	s.actor(
		&"npc",
		&"invader",
		Vector2(200, 200),
		{ "movement:speed": 0.0, "facing": Vector2.RIGHT },
	)
	s.actor(&"tgt", &"puppet", TARGET, { "faction": &"household", "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"npc", &"debug_state")
	var claimed := -1
	var asked := -1
	for frame in 90:
		await t.frames(1)
		if claimed < 0 and int(brain.debug_state()["decisions"]) > 0:
			claimed = frame
		if asked < 0 and not DecisionStub.requests.is_empty():
			asked = frame
		if claimed >= 0 and asked >= 0:
			break
	if not t.require(claimed >= 0 and asked >= 0, "a decision was claimed and Von was asked"):
		return
	t.check(
		asked - claimed >= PIECES_BEFORE_THE_ASK,
		"Von was asked %d frames after the claim (at least %d)"
			% [asked - claimed, PIECES_BEFORE_THE_ASK],
	)
	var landed := await t.until(
		func(): return (brain.debug_state()["decision"]["levels"] as Array).size() >= 2, 3.0
	)
	t.check(landed, "the walk went through its levels over the frames")
	t.check(not bool(brain.debug_state()["decision"]["last_failed"]), "and did not fail")
