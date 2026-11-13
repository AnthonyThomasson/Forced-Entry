extends GameTest
## A teammate's stack slot claimed while the decision job searches for a throw or builds the
## throws it found is seen by the entries the walk reads. The group piece builds the entries
## (their picks claim a slot from the live ledger, `SnapshotOptions._entry_pick`) before the throw
## piece, so the callouts read again as the walk begins (`AgentSnapshot.reread_claims`) make the
## entries again when a claim came in since: two NPCs bound for one doorway then take different
## slots however long the decision takes.
##
## The scene of `ai/decision/claim_seen_during_group_piece` with a stun carried (the entries are
## built ahead of the walk) and the throw search costing a unit a step: the invader's decision is in
## its throw piece for frames, the ally claims slot 1 at the doorway of the entry the snapshot
## offers first, and the walk's entry for that doorway is a slot after it. A second ally's combat
## call in the same window is a lead of the walk's (the leads read the calls as the entries do).

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Job := preload("res://scenes/ai/decision/decision_job.gd")
const NPC_POS := Vector2(960, 190)
const TARGET_POS := Vector2(660, 120)
const ALLY_POS := Vector2(1100, 300)
const CALLER_POS := Vector2(1100, 360)


func describe() -> Dictionary:
	return {
		"name": "A slot claimed during the throw piece is seen by the entries the walk reads",
		"description": "With the entries built ahead of the walk and every throw search step "
			+ "costing a unit of the pool, an ally's claim of slot 1 at a doorway that comes in "
			+ "while the decision searches for a throw moves the NPC's own slot there to a later "
			+ "one in the snapshot the walk begins with.",
		"tags": ["ai", "decision", "entry", "callout", "snapshot", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Flank.rules(s)
	s.set_static(DecisionBudget, "per_frame", 1)
	s.set_static(DecisionBudget, "cost_group_unit", 0)
	s.set_static(DecisionBudget, "cost_throw_block", 1)
	s.set_static(DecisionBudget, "cost_throw_rank", 1)
	s.set_static(DecisionBudget, "cost_throw_route", 1)
	# A decision starts at the root, not the fight's node (as `claim_seen_during_group_piece`).
	Flank.npc(
		s,
		&"npc",
		NPC_POS,
		{ "tuning:combat:engage_dwell": 0.05, "tuning:decision:pursue_hostiles": false },
		{ "look_at": TARGET_POS },
	)
	GrenadeAi.hostile(s, &"target", TARGET_POS, Maps.DOOR_BACK)
	Flank.ally(s, &"radio_ally", ALLY_POS)
	Flank.ally(s, &"caller", CALLER_POS)


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"npc"), 1, 1)  # a frag and a stun: the entries are built ahead
	var brain := t.controller(&"npc", &"current_act")
	var job: RefCounted = brain.get("_job")
	if not await Flank.settle(t, brain):
		return
	var perception: Node = brain.get("_perception")
	if not await t.until(func(): return not perception.quick_facts()["engaged"], 5.0):
		return
	brain.get("_cadence").force("probe")
	var searching := await t.until(func(): return job.get("_stage") == Job.Stage.THROW, 10.0)
	if not t.require(searching, "set-up: a decision is searching for a throw"):
		return
	var offered := _entries(job.get("_snapshot"))
	if not t.require(not offered.is_empty(), "set-up: the entries were built ahead of the walk"):
		return
	var first: Dictionary = offered[0]["params"]
	t.expect_eq(first["slot"], 1, "premise: the NPC takes slot 1 while it is free")
	Entry.radio_claim(
		t.actor(&"radio_ally"),
		String(first["opening"]),
		String(first["into"]),
		Vector2i(1, 1),
		GameClock.frame(),
	)
	var lead := "lead_ally_%d" % t.actor(&"caller").get_instance_id()
	t.check(not _leads(job.get("_snapshot")).has(lead), "premise: no lead to the caller yet")
	Flank.radio(t, &"caller", CALLER_POS)
	var frames := 0
	while _building(job) and frames < 60:
		await t.frames(1)
		frames += 1
	if not t.require(
		frames >= 2 and frames < 60,
		"set-up: the search went on, then ended (%d)" % frames,
	):
		return
	var seen := _entries(job.get("_snapshot")).filter(
		func(o): return o["params"]["opening"] == first["opening"]
	)
	t.check(_leads(job.get("_snapshot")).has(lead), "the walk's leads include the caller's call")
	var slots := seen.map(func(o): return o["params"]["slot"])
	t.check(
		not slots.is_empty() and int(slots[0]) != 1,
		"the NPC's slot at the doorway is not the ally's (%s)" % [slots],
	)


## Whether the decision's walk has not begun.
func _building(job: RefCounted) -> bool:
	var stage: int = job.get("_stage")
	return stage == Job.Stage.GROUP or stage == Job.Stage.THROW or stage == Job.Stage.GRENADE


## The ENTER options of the snapshot's entries as the walk reads them (built now unless built).
func _entries(snapshot: Dictionary) -> Array:
	return snapshot["demand"].group("entries")["options"]


## The ids of the lead options of the snapshot's leads as the walk reads them.
func _leads(snapshot: Dictionary) -> Array:
	return snapshot["demand"].group("leads")["options"].map(func(o): return o["id"])
