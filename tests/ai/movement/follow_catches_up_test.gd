extends GameTest
## LD21: a follower runs until it has caught up. A puppet stands in for the human leader of a squad
## of one invader NPC (`s.squads` with `human`) and walks a long straight line down an open hall at
## its walking pace, pausing halfway to look back; the NPC starts far behind its follow spot. It
## runs once it is more than `FOLLOW_STEP` from its live spot, and keeps running until it is back
## within `FOLLOW_CAUGHT_UP` of it, so the file closes up: a run that stopped at `FOLLOW_STEP` would
## leave it walking at its leader's pace that far behind its spot for the rest of the walk.
##
## Two things try the run. During the first catch-up, once the NPC is within `FOLLOW_STEP` of its
## spot, a teammate steps into its way and out again as soon as it has stood a moment: the stop
## does not end the catch-up, so the test counts a run through a pause in the running shorter than
## `RUN_GAP_S` as one catch-up, judged where it ends. And at the leader's pause the NPC comes up to
## it and, as the leader looks back down the hall, steps out of its way: when the leader turns and
## walks on, the NPC is well off its spot again and must catch up a second time. The leader looks
## back because a plain pause does not do it: the NPC then sets off a step behind its leader and
## stays within `FOLLOW_STEP` of its spot, so it never runs.
##
## Real Von, the whole pipeline; no switch. Nobody is hostile, so the follower has nothing to shoot
## and puts no question to Von. The teammate is a puppet the test puts down and takes away.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const HALL := Rect2(0, 0, 2600, 600)
## The human's walk: one straight line down the hall, eastward, with a pause at `PAUSE_AT`.
const FROM := Vector2(300, 300)
const PAUSE_AT := Vector2(1300, 300)
const TO := Vector2(2450, 300)
## How long (s) the human stands at `PAUSE_AT`, looking back at `FROM`: past `FOLLOW_STILL_TIME`,
## so the NPC comes up to its ring spot, and then out of the human's way.
const PAUSE_S := 2.5
## Where the follower starts: well over `FOLLOW_STEP` behind its spot (the first follower's,
## `FOLLOW_GAP` behind the human).
const NPC_AT := Vector2(40, 300)
## Where the teammate waits when it is not in the way: behind everyone, at the hall's edge.
const PARKED := Vector2(60, 560)
## The teammate steps in once the running NPC is this close (px) to its spot: within `FOLLOW_STEP`,
## with room for the spot to draw away while it stands.
const STEP_IN_WITHIN := 32.0
## How far (px) ahead of the NPC, toward its spot, the teammate stands: just past the spot, so the
## NPC's walk there is held short of it.
const STEP_IN := 50.0
## How many physics frames the NPC stands for the teammate before it steps out again, and the
## longest (s) it waits for that.
const STOOD_FRAMES := 2
const STEP_IN_MAX_S := 0.5
## A pause in the running shorter than this (s) does not end a run: the run the test judges is the
## catch-up, through a stop for a body in the way.
const RUN_GAP_S := 0.5
## How long (s) after a catch-up run ends its closest approach to its spot is taken (the run ends
## within `FOLLOW_CAUGHT_UP` of it, a few frames' slowing at most).
const SETTLE_S := 0.5
## The invader's `run_start_fraction`: a run that ended with its stamina below this ran dry, and is
## not a catch-up the follower chose to end.
const RUN_START := 0.5


func describe() -> Dictionary:
	return {
		"name": "A follower runs until it has caught up",
		"description": "A puppet human leader walks a long straight line, pausing halfway to look "
			+ "back: its NPC follower, starting far behind, runs to catch up and keeps running "
			+ "until it is back within follow_caught_up of its spot, through a teammate stepping "
			+ "into its way, and again after the pause.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "run", "von"],
		"requires_von": true,
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	Stack.human(s, &"me", FROM, { "movement:aim_point": TO })
	s.actor(&"m", &"invader", NPC_AT)
	Stack.human(s, &"mate", PARKED, { "movement:aim_point": PARKED + Vector2.UP * 300 })
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(squad.leader() == me, "the human leads (premise: Lead the team)"):
		return
	if not t.require(squad.follows(m), "premise: the NPC follows the human (Squad.follows)"):
		return
	var rec := Record.new()
	rec.squad = squad
	rec.w = Follow.new_watch()
	var walked_on := await _walk(t, rec)
	if not _walked(t, rec, m):
		return
	var runs := _runs(rec.samples)
	var catch_ups := _catch_ups(t, runs, rec.step_in, walked_on)
	if catch_ups.is_empty():
		return
	var short: Array = catch_ups.filter(
		func(r): return float(r["closest"]) > Follow.FOLLOW_CAUGHT_UP
	)
	t.check(
		short.is_empty(),
		"after each catch-up the NPC came back within %.0f px of its spot (%d of %d runs did not; "
			% [Follow.FOLLOW_CAUGHT_UP, short.size(), catch_ups.size()]
			+ "the first such: %s)" % [short[0] if not short.is_empty() else "-"],
	)
	var tuned: Variant = squad.get("follow_caught_up")
	t.check(
		tuned != null and is_equal_approx(float(tuned), Follow.FOLLOW_CAUGHT_UP),
		"the squad's follow_caught_up is LD21's (%s, not %s)"
			% [tuned, Follow.FOLLOW_CAUGHT_UP],
	)
	t.expect_eq(Follow.asked(rec.w, m), 0, "the follower asked Von nothing")


## The human's walk: to `PAUSE_AT`, a pause looking back at `FROM`, then on to `TO`, watched all the
## way; when it walked on from the pause (sim s).
func _walk(t: TestContext, rec: Record) -> float:
	var puppet := t.puppet(&"me")
	puppet.walk_to(PAUSE_AT)
	await _watch(t, rec, func(): return puppet.has_arrived(), 30.0)
	puppet.aim_at(FROM)
	var pause_end := t.time + PAUSE_S
	await _watch(t, rec, func(): return t.time >= pause_end, PAUSE_S + 1.0)
	puppet.aim_at(TO)
	puppet.walk_to(TO)
	var walked_on := t.time
	await _watch(t, rec, func(): return puppet.has_arrived(), 30.0)
	return walked_on


## The premises of the walk: the NPC followed, the human reached the end of the hall and the
## teammate stepped into the NPC's catch-up; false when one fails.
func _walked(t: TestContext, rec: Record, m: Node) -> bool:
	if not t.require(
			Follow.took(rec.w, m, "follow"),
			"the NPC follows the human (FOLLOW; acts %s)" % Follow.acts_of(rec.w, m),
	):
		return false
	if not t.require(
			t.puppet(&"me").has_arrived(),
			"premise: the human walked to the end of the hall",
	):
		return false
	var step_in := rec.step_in
	return t.require(
		step_in["state"] == "done" and float(step_in["stood_off"]) <= Follow.FOLLOW_STEP,
		"premise: the teammate stepped into the NPC's catch-up and the NPC stood for it within "
			+ "%.0f px of its spot (%s)" % [Follow.FOLLOW_STEP, step_in],
	)


## The catch-up runs of `runs` (those that ended with stamina to spare), once the one the teammate
## stepped into is one and there are some before and after the human walked on at `walked_on`;
## empty when a premise fails.
func _catch_ups(t: TestContext, runs: Array, step_in: Dictionary, walked_on: float) -> Array:
	var catch_ups: Array = runs.filter(func(r): return float(r["stamina"]) >= RUN_START)
	var stepped_into: Array = runs.filter(func(r): return float(r["end"]) >= float(step_in["at"]))
	if not t.require(
			not stepped_into.is_empty() and float(stepped_into[0]["stamina"]) >= RUN_START,
			"premise: the catch-up the teammate stepped into ended with stamina to spare, so it "
				+ "is judged (runs %s)" % [runs],
	):
		return []
	if not t.require(
			catch_ups.size() >= 2
				and catch_ups.any(func(r): return float(r["end"]) < walked_on)
				and catch_ups.any(func(r): return float(r["end"]) >= walked_on),
			"premise: the NPC ran to catch up at least twice, before the human walked on from its "
				+ "pause at %.1f s and after (runs %s)" % [walked_on, runs],
	):
		return []
	return catch_ups


## Sample the human and the NPC every physics frame into `rec` until `done` holds (at most
## `limit_s` sim s), putting the teammate into the NPC's first catch-up as `rec.step_in` says.
func _watch(t: TestContext, rec: Record, done: Callable, limit_s: float) -> void:
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	var end := t.time + limit_s
	while not done.call() and t.time < end:
		Follow.tick(rec.w, t, [me, m], rec.squad)
		var spot: Vector2 = rec.squad.follow_spot(m)
		var d: float = m.global_position.distance_to(spot)
		rec.samples.append([t.time, d, m.movement.is_running(), m.movement.stamina_fraction()])
		_step_in(t, rec.step_in, m, spot, d)
		t.trace("off spot", d)
		await t.frames(1)


## The teammate's step into the NPC's way: put down `STEP_IN` px ahead of the running NPC once it
## is within `STEP_IN_WITHIN` of its spot, taken away once the NPC has stood `STOOD_FRAMES` frames
## for it (or after `STEP_IN_MAX_S`). `state` goes `waiting`, `in`, `done`; `stood_off` is how far
## the NPC was from its spot when it stood.
func _step_in(t: TestContext, step_in: Dictionary, m: Node, spot: Vector2, d: float) -> void:
	var mate := t.actor(&"mate")
	match step_in["state"]:
		"waiting":
			if m.movement.is_running() and d <= STEP_IN_WITHIN and d > Follow.FOLLOW_CAUGHT_UP:
				var here: Vector2 = m.global_position
				mate.global_position = here + (spot - here).normalized() * STEP_IN
				step_in.merge({ "state": "in", "at": t.time, "off": d, "stood": 0 }, true)
		"in":
			if m.movement.move_input == Vector2.ZERO:
				if int(step_in["stood"]) == 0:
					step_in["stood_off"] = d
				step_in["stood"] = int(step_in["stood"]) + 1
			if (int(step_in["stood"]) >= STOOD_FRAMES
					or t.time - float(step_in["at"]) >= STEP_IN_MAX_S):
				mate.global_position = PARKED
				step_in["state"] = "done"
				step_in["out"] = t.time
				step_in["off_out"] = d


## The runs in `samples`, a pause in the running shorter than `RUN_GAP_S` kept inside one: per run
## `{ end` (sim s of its last running frame)`, off` (px off its spot then)`, closest` (the least
## px off its spot within `SETTLE_S` after)`, stamina` (at its end) `}`. A run still going at the
## last sample is left out.
func _runs(samples: Array) -> Array:
	var out: Array = []
	var last := -1
	for i in samples.size():
		var s: Array = samples[i]
		if bool(s[2]):
			if last >= 0 and float(s[0]) - float(samples[last][0]) > RUN_GAP_S:
				out.append(_run_end(samples, last))
			last = i
	if last >= 0 and float(samples.back()[0]) - float(samples[last][0]) > RUN_GAP_S:
		out.append(_run_end(samples, last))
	return out


## The run that ended at sample `i` of `samples`, as `_runs` gives it.
func _run_end(samples: Array, i: int) -> Dictionary:
	var end: float = samples[i][0]
	var closest: float = samples[i][1]
	for j in range(i, samples.size()):
		if float(samples[j][0]) - end > SETTLE_S:
			break
		closest = minf(closest, float(samples[j][1]))
	return {
		"end": snappedf(end, 0.01),
		"off": snappedf(float(samples[i][1]), 0.1),
		"closest": snappedf(closest, 0.1),
		"stamina": snappedf(float(samples[i][3]), 0.01),
	}


## What the walk is watched into: the team's record (`Follow.tick`) with the squad that names the
## leader, one sample a frame (`[sim s, px off its spot, running, stamina]`) and the teammate's step
## into the NPC's way (`_step_in`).
class Record:
	var w: Dictionary = {}
	var squad: Node
	var samples: Array = []
	var step_in: Dictionary = { "state": "waiting" }
