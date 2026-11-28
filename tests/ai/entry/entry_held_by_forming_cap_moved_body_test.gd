extends "res://tests/ai/entry/entry_held_by_forming_stack_cap_test.gd"
## The cap of `entry_held_by_forming_stack_cap` when another body at rest on the walker's way (one
## that does not hold the walk) shifts a few pixels part-way through the hold (#194): the
## map the verdict on the slot is read from (`AgentEntry.slot_reach`, carving the bodies at rest) is
## asked for just before each reader needs it, not only before the walk's re-plan
## (`EntryApproach.WARM_LEAD`): the reader at the cap (`_end_forming_wait`) too. So the invader
## gives its slot up (the back of the stack) at the cap plus the avoid map's landing
## (`NavBakeConfig.avoid_frames`), not at the walk's next re-plan, a few seconds later (`Locomotion`
## re-plans a held walk every `REPLAN_EVERY` s).

## Where a bystander stands behind the teammate in the gap, off the walker's way but within the
## corridor of bodies a verdict carves (`AgentEntry.BODY_CORRIDOR`).
const BYSTANDER := Vector2(ROW_X + 60.0, 352.0)
## How far into the hold (s) the bystander shifts: past the walk's first re-plan, before
## the warm-up of the cap's reader.
const SHIFT_AT := 1.9
## How far (px) it shifts along the gap: more than the avoid maps' tolerance (`EntryBodyMaps`),
## and past where a walk to a point stops short of it.
const SHIFT := 16.0
## The latest (s into the hold) its slot may rise: the cap, then the radio's claim a moment after
## (the unshifted case rises 0.8 s after it). The walk's next re-plan after the first is at 4.75 s.
const LATEST := 4.0

var _shifted := false


func configure(s: TestSetup) -> void:
	super(s)
	s.actor(&"bystander", &"puppet", BYSTANDER, { "faction": &"invader", "max_health": 1.0e6 })


func describe() -> Dictionary:
	return {
		"name": "A walk held past the cap gives its slot up at the cap, a bystander shifted",
		"description": "A bystander behind the teammate in the only gap shifts a few pixels "
			+ "part-way through the hold; the invader's verdict on its slot is still read at the "
			+ "cap (the map asked for before it), not at the next re-plan.",
		"tags": ["ai", "entry", "stack", "navigation", "scripted"],
		"timeout": 40.0,
	}


func _watch(
		t: TestContext,
		st: Dictionary,
		walker: Node,
		brain: Node,
		claim_frame: int,
) -> bool:
	if not _shifted and float(st["held_bare"]) >= SHIFT_AT:
		_shifted = true
		t.puppet(&"bystander").walk_to(BYSTANDER + Vector2(SHIFT, 0.0))
	return super(t, st, walker, brain, claim_frame)


func _judge(t: TestContext, st: Dictionary) -> void:
	var held_to_rise := float(st["rise_at"]) - float(st["held_bare_at"])
	t.check(_shifted, "premise: the bystander shifted")
	t.check(
		st["rise_at"] != INF and held_to_rise <= LATEST,
		("it takes the back of the stack by the cap and the map's landing, not at the next re-plan "
				+ "(the slot rose %.2f s into the hold, the latest %.2f s)") % [
					held_to_rise,
					LATEST,
				],
	)
