extends GameTest
## A teammate's radio claim that lands while the decision job is searching for a throw (its priced
## throw piece spanning frames, between the build and the walk) is in the snapshot the walk begins
## with: the callouts are read again as the throw piece ends, the last thing before the walk
## (`AgentPerception.reread_claims`), not at the order-refusal step before the search. Two NPCs on
## one target then take different sides however long a decision takes.
##
## The scene of `ai/decision/claim_seen_as_the_walk_begins`, with every throw step costing the
## pool's one unit: the invader's decision stays in its throw piece for frames, the ally radios the
## target's left in the middle of it, and the first walk made after reads the left side as the
## ally's.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Job := preload("res://scenes/ai/decision/decision_job.gd")
## The invader outside the Terrace house's back door and the householder it sees through the
## doorway off its axis: its lob from the hand clears no jamb, so the throw search has a throw spot
## to look for, over several steps (`ai/decision/throw_piece_matches_whole`).
const NPC_POS := Vector2(960, 190)
const TARGET_POS := Vector2(660, 120)
const ALLY_POS := Vector2(1100, 300)


func describe() -> Dictionary:
	return {
		"name": "A claim radioed during the throw piece is seen as the walk begins",
		"description": "With every throw search step costing a unit of the pool, a teammate's "
			+ "claim of the target's left that comes in while the decision is searching for a "
			+ "throw is the held-by of that side in the snapshot the walk begins with.",
		"tags": ["ai", "decision", "flank", "callout", "snapshot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Flank.rules(s)
	s.set_static(DecisionBudget, "per_frame", 1)
	s.set_static(DecisionBudget, "cost_throw_block", 1)
	s.set_static(DecisionBudget, "cost_throw_rank", 1)
	s.set_static(DecisionBudget, "cost_throw_route", 1)
	Flank.npc(s, &"npc", NPC_POS, {}, { "look_at": TARGET_POS })
	GrenadeAi.hostile(s, &"target", TARGET_POS, Maps.DOOR_BACK)
	Flank.ally(s, &"radio_ally", ALLY_POS)


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"npc"), 1, 1)  # it carries a frag: there is a throw to search for
	var brain := t.controller(&"npc", &"current_act")
	var job: RefCounted = brain.get("_job")
	var target_id: int = t.actor(&"target").get_instance_id()
	if not await Flank.settle(t, brain):
		return
	# The target's left as the NPC measures it: in the target's own frame (its front).
	var targets: Dictionary = job.get("_snapshot")["demand"].targets
	if not t.require(targets.has(target_id), "set-up: the NPC analysed the target"):
		return
	var front := Vector2.from_angle(targets[target_id]["a"]["front"])
	var left := Flank.side_point(TARGET_POS, front, "left")
	# A new decision, forced: it is in its throw piece for frames, and the claim goes out then.
	brain.get("_cadence").force("probe")
	var searching := await t.until(func(): return job.get("_stage") == Job.Stage.THROW, 10.0)
	if not t.require(searching, "set-up: a decision is searching for a throw"):
		return
	var before := _left(job.get("_snapshot"), target_id)
	t.expect_eq(before["tags"]["held_by"], "", "premise: the side is free as the search begins")
	Flank.radio(t, &"radio_ally", left)
	var frames := 0
	while job.get("_stage") == Job.Stage.THROW and frames < 60:
		await t.frames(1)
		frames += 1
	# The claim was heard while the search went on (two frames at least: it is posted, then read).
	if not t.require(
		frames >= 2,
		"set-up: the search went on for frames after the claim (%d)" % frames,
	):
		return
	if not t.require(frames < 60, "set-up: the search ended"):
		return
	var seen := _left(job.get("_snapshot"), target_id)
	t.expect_eq(
		seen["tags"]["held_by"],
		"radio_ally (radio)",
		"the left side is the ally's in the walk's snapshot",
	)


## The flank option of the target's left side in `snapshot`, or {}.
func _left(snapshot: Dictionary, target_id: int) -> Dictionary:
	var group: Dictionary = snapshot["options"]["per_target"][target_id]["flank_sides"]
	for o: Dictionary in group["options"]:
		if o["id"] == "side_left":
			return o
	return {}
