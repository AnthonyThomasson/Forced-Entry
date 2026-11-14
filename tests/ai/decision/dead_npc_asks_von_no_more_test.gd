extends GameTest
## An NPC killed while Von's answer to one of its levels is on the way does not go on with that
## decision: the late answer neither walks the next level (a question asked of Von for a corpse) nor
## adopts a leaf on the dead body. The controller drops the job on the character's `died`
## (`DecisionJob.cancel`), not only its place in the pool's roster. One invader sees a trespasser;
## its answers are held back several frames, so its first question is outstanding when it is killed.

const TARGET := Vector2(700, 200)
## Frames a scripted answer is held back: long enough to kill the NPC with its question outstanding.
const LATENCY := 6
## Frames watched after the death: the held answer lands within them.
const WATCH_FRAMES := 20


func describe() -> Dictionary:
	return {
		"name": "A dead NPC's late Von answer walks nothing",
		"description": "An invader killed with a question outstanding asks Von nothing more, "
			+ "holds no decision in flight and keeps the pick it had when it died.",
		"tags": ["ai", "decision", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 400))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }], LATENCY)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.actor(
		&"npc",
		&"invader",
		Vector2(200, 200),
		{ "movement:speed": 0.0, "facing": Vector2.RIGHT },
	)
	s.actor(&"tgt", &"puppet", TARGET, { "faction": &"household", "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"debug_state")
	var job: RefCounted = brain.get("_job")
	var asked := await t.until(
		func() -> bool: return job.call("walking") and not DecisionStub.requests.is_empty(), 4.0
	)
	if not t.require(asked, "set-up: the invader's walk asked Von its first question"):
		return
	npc.take_damage(1_000_000.0)
	await t.frames(1)
	if not t.require(npc.is_dead, "set-up: the invader is dead with its question outstanding"):
		return
	var asks := DecisionStub.requests.size()
	var levels := (brain.debug_state()["decision"]["levels"] as Array).size()
	await t.frames(WATCH_FRAMES)
	t.expect_eq(DecisionStub.requests.size(), asks, "Von was asked nothing for the corpse")
	t.check(not bool(job.call("pending")), "no decision of the corpse is in flight")
	t.expect_eq(
		(brain.debug_state()["decision"]["levels"] as Array).size(),
		levels,
		"the held answer walked no level of the dead NPC's decision",
	)
