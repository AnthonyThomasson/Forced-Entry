extends RefCounted
## Shared set-up of the tests that an NPC whose decision is in flight and that never advances again
## frees the pool for the next one (`ai/decision/dead_npc_frees_the_pool`,
## `freed_npc_frees_the_pool`): two invaders that see a trespasser at once, a pool of one unit a
## frame and every piece of a decision priced, so the first to claim stays mid-build for frames and
## the other waits its turn behind it (the roster serves the oldest claim first).

const TARGET := Vector2(900, 60)
## The most frames the younger one is watched for after the older one is gone.
const WATCH_FRAMES := 8


## Two invaders, `elder` first in the tree, and the trespasser, with every piece priced.
static func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1800, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.set_static(DecisionBudget, "per_frame", 1)
	s.set_static(DecisionBudget, "cost_hostile", 1)
	s.set_static(DecisionBudget, "cost_finish", 1)
	s.set_static(DecisionBudget, "cost_refusal", 1)
	s.set_static(DecisionBudget, "cost_level", 1)
	for i in 2:
		var at := Vector2(150 + i * 200, 300)
		s.actor(
			StringName("inv%d" % i),
			&"invader",
			at,
			{ "movement:speed": 0.0, "facing": (TARGET - at).normalized() },
		)
	s.actor(&"tgt", &"puppet", TARGET, { "faction": &"household", "max_health": 100_000.0 })


## Both want a decision on the first frame; the elder claims and is left mid-build, the younger
## waits. Then `remove` does something to the elder, `confirm` (a premise, checked a frame later)
## says it happened, and the younger either claims on the very next frame (`frees`: the elder is
## gone, not three frames later when the roster would forget it) or waits behind the elder, which
## still owes the pool (not `frees`: it is only moved, and keeps its place). Each frame counts
## physics frames, so the younger's wait is exact whatever the machine's load.
static func run(t: TestContext, remove: Callable, confirm: Callable, frees := true) -> void:
	var elder := t.controller(&"inv0", &"debug_state")
	var younger := t.controller(&"inv1", &"debug_state")
	for brain in [elder, younger]:
		brain.get("_cadence").force("probe")
	var job: RefCounted = elder.get("_job")
	var in_flight := false
	for frame in 20:
		await t.frames(1)
		if int(elder.debug_state()["decisions"]) > 0 and job.call("frozen"):
			in_flight = true
			break
	if not t.require(in_flight, "set-up: the elder claimed and is building over frames"):
		return
	t.expect_eq(
		int(younger.debug_state()["decisions"]), 0, "premise: the younger waits behind the elder"
	)
	remove.call()
	await t.frames(1)
	if not t.require(confirm.call(), "set-up: the elder is as the test left it"):
		return
	var claimed := int(younger.debug_state()["decisions"]) > 0
	var waited := 1
	while not claimed and waited < WATCH_FRAMES:
		await t.frames(1)
		waited += 1
		claimed = int(younger.debug_state()["decisions"]) > 0
	t.check(claimed, "the younger claimed at all")
	if frees:
		t.expect_eq(
			waited,
			1,
			"the younger claimed on the very next frame after the elder was gone",
		)
	else:
		t.check(waited > 1, "the younger waited behind the elder, which still owes the pool")
