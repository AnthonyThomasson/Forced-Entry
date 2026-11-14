extends GameTest
## A teammate's radio claim that lands while the decision job is building the groups the root reads
## (its priced group piece, a lead or a doorway a step, spanning frames between the order-refusal
## step and the throw search) is in the snapshot the walk begins with: the callouts are read again
## after the last piece, the last thing before the walk (`AgentPerception.reread_claims`), not at
## the order-refusal step before the groups. Two NPCs on one target then take different sides
## however long the groups take.
##
## The scene of `ai/decision/claim_seen_during_throw_piece` with the leads' gunfire heard in three
## rooms, a unit of the group piece costing the pool's one unit and the throw search free: the
## invader's decision stays in its group piece for frames (it starts at the root: nothing engages
## it), the ally radios the target's left in the middle of it, and the first walk made after reads
## the left side as the ally's.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Job := preload("res://scenes/ai/decision/decision_job.gd")
const NPC_POS := Vector2(960, 190)
const TARGET_POS := Vector2(660, 120)
const ALLY_POS := Vector2(1100, 300)
## Where gunfire is heard (distinct 200 px cells: a lead each).
const HEARD := [Vector2(300, 300), Vector2(500, 120), Vector2(700, 330)]


func describe() -> Dictionary:
	return {
		"name": "A claim radioed during the group piece is seen as the walk begins",
		"description": "With every unit of the group piece costing a unit of the pool, a "
			+ "teammate's claim of the target's left that comes in while the decision builds the "
			+ "leads is the held-by of that side in the snapshot the walk begins with.",
		"tags": ["ai", "decision", "flank", "callout", "snapshot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Flank.rules(s)
	s.set_static(DecisionBudget, "per_frame", 1)
	s.set_static(DecisionBudget, "cost_group_unit", 1)
	s.set_static(DecisionBudget, "cost_throw_block", 0)
	s.set_static(DecisionBudget, "cost_throw_rank", 0)
	s.set_static(DecisionBudget, "cost_throw_route", 0)
	# A decision starts at the root, not the fight's node, for an NPC that does not pursue the
	# hostile it knows (a defender's) once the fight's commitment has lapsed (the dwell is short);
	# the premise of this test, as it is the premise of the group piece.
	Flank.npc(
		s,
		&"npc",
		NPC_POS,
		{ "tuning:combat:engage_dwell": 0.05, "tuning:decision:pursue_hostiles": false },
		{ "look_at": TARGET_POS },
	)
	GrenadeAi.hostile(s, &"target", TARGET_POS, Maps.DOOR_BACK)
	Flank.ally(s, &"radio_ally", ALLY_POS)


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"npc"), 0, 1)  # a frag only: no stun in the stack
	var brain := t.controller(&"npc", &"current_act")
	var job: RefCounted = brain.get("_job")
	var target_id: int = t.actor(&"target").get_instance_id()
	for at: Vector2 in HEARD:
		EventBus.post(
			&"hit",
			{
				"position": at, "direction": Vector2.LEFT, "damage": 10.0, "attacker": null,
				"victim": null,
			},
		)
	if not await Flank.settle(t, brain):
		return
	# A new decision, forced once the fight's commitment has lapsed (the dwell is short): it starts
	# at the root with the target in view, is in its group piece for frames, and the claim goes out
	# then.
	var perception: Node = brain.get("_perception")
	if not await t.until(func(): return not perception.quick_facts()["engaged"], 5.0):
		return
	brain.get("_cadence").force("probe")
	var building := await t.until(
		func(): return job.get("_stage") == Job.Stage.GROUP and _analysed(job, target_id), 10.0
	)
	if not t.require(building, "set-up: a decision is building its groups with the target known"):
		return
	var front := Vector2.from_angle(_targets(job)[target_id]["a"]["front"])
	var left := Flank.side_point(TARGET_POS, front, "left")
	var before := _left(job.get("_snapshot"), target_id)
	t.expect_eq(before["tags"]["held_by"], "", "premise: the side is free as the groups begin")
	Flank.radio(t, &"radio_ally", left)
	var frames := 0
	while _building(job) and frames < 60:
		await t.frames(1)
		frames += 1
	if not t.require(
		frames >= 2,
		"set-up: the groups went on for frames after the claim (%d)" % frames,
	):
		return
	if not t.require(frames < 60, "set-up: the build ended"):
		return
	var seen := _left(job.get("_snapshot"), target_id)
	t.expect_eq(
		seen["tags"]["held_by"],
		"radio_ally (radio)",
		"the left side is the ally's in the walk's snapshot",
	)


## The hostiles the job's snapshot analysed, by id.
func _targets(job: RefCounted) -> Dictionary:
	var snapshot: Dictionary = job.get("_snapshot")
	return snapshot["demand"].targets if snapshot.has("demand") else {}


## Whether the job's snapshot analysed hostile `id`.
func _analysed(job: RefCounted, id: int) -> bool:
	return _targets(job).has(id)


## Whether the decision's walk has not begun: its groups, its throw search or the throws it found
## are being built (the callouts are read again as the last of them ends).
func _building(job: RefCounted) -> bool:
	var stage: int = job.get("_stage")
	return stage == Job.Stage.GROUP or stage == Job.Stage.THROW or stage == Job.Stage.GRENADE


## The flank option of the target's left side in `snapshot`, or {}.
func _left(snapshot: Dictionary, target_id: int) -> Dictionary:
	var group: Dictionary = snapshot["options"]["per_target"][target_id]["flank_sides"]
	for o: Dictionary in group["options"]:
		if o["id"] == "side_left":
			return o
	return {}
