extends GameTest
## LD21: a follower runs until it has caught up. A puppet stands in for the human leader of a squad
## of one invader NPC (`s.squads` with `human`) and walks a long straight line down an open hall at
## its walking pace; the NPC starts far behind its follow spot. It runs once it is more than
## `FOLLOW_STEP` from its live spot, and keeps running until it is back within `FOLLOW_CAUGHT_UP`
## of it, so the file closes up: a run that stopped at `FOLLOW_STEP` would leave it walking at its
## leader's pace that far behind its spot for the rest of the walk.
##
## Real Von, the whole pipeline; no switch. Nobody is hostile, so the follower has nothing to shoot
## and puts no question to Von.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const HALL := Rect2(0, 0, 2600, 600)
## The human's walk: one straight line down the hall, eastward.
const FROM := Vector2(300, 300)
const TO := Vector2(2450, 300)
## Where the follower starts: well over `FOLLOW_STEP` behind its spot (the first follower's,
## `FOLLOW_GAP` behind the human).
const NPC_AT := Vector2(40, 300)
## How long (s) after a catch-up run ends its closest approach to its spot is taken (the run ends
## within `FOLLOW_CAUGHT_UP` of it, a few frames' slowing at most).
const SETTLE_S := 0.5


func describe() -> Dictionary:
	return {
		"name": "A follower runs until it has caught up",
		"description": "A puppet human leader walks a long straight line: its NPC follower, "
			+ "starting far behind, runs to catch up and keeps running until it is back within "
			+ "follow_caught_up of its spot, not just within follow_step.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "run", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	Stack.human(s, &"me", FROM, { "aim_point": TO })
	s.actor(&"m", &"invader", NPC_AT)
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(squad.leader() == me, "the human leads (premise: Lead the team)"):
		return
	if not t.require(squad.follows(m), "premise: the NPC follows the human (Squad.follows)"):
		return
	var puppet := t.puppet(&"me")
	puppet.walk_to(TO)
	var w := Follow.new_watch()
	# Per catch-up run that ended while the human walked: `[when it ended (sim s), the closest (px)
	# the NPC came to its spot within `SETTLE_S` of that]`.
	var catch_ups: Array = []
	var was_running := false
	while not puppet.has_arrived() and t.time < 40.0:
		Follow.tick(w, t, [me, m], squad)
		var d: float = m.global_position.distance_to(squad.follow_spot(m))
		var running: bool = m.is_running()
		if was_running and not running:
			catch_ups.append([t.time, d])
		elif not catch_ups.is_empty() and t.time - float(catch_ups.back()[0]) <= SETTLE_S:
			catch_ups.back()[1] = minf(float(catch_ups.back()[1]), d)
		was_running = running
		t.trace("off spot", d)
		await t.frames(1)

	if not t.require(
			Follow.took(w, m, "follow"),
			"the NPC follows the human (FOLLOW; acts %s)" % Follow.acts_of(w, m),
	):
		return
	if not t.require(
			not catch_ups.is_empty() and puppet.has_arrived(),
			"premise: the NPC ran to catch up and stopped running while the human walked to its "
				+ "end (catch-ups %s, the human there %s)" % [catch_ups, puppet.has_arrived()],
	):
		return
	var short: Array = catch_ups.filter(func(c): return float(c[1]) > Follow.FOLLOW_CAUGHT_UP)
	t.check(
		short.is_empty(),
		"after each catch-up the NPC came back within %.0f px of its spot (%d of %d runs did not; "
			% [Follow.FOLLOW_CAUGHT_UP, short.size(), catch_ups.size()]
			+ "the first such: ended at %s, the closest %s px within %.1f s)"
			% [
				"%.1f s" % float(short[0][0]) if not short.is_empty() else "-",
				"%.0f" % float(short[0][1]) if not short.is_empty() else "-",
				SETTLE_S,
			],
	)
	var tuned: Variant = squad.get("follow_caught_up")
	t.check(
		tuned != null and is_equal_approx(float(tuned), Follow.FOLLOW_CAUGHT_UP),
		"the squad's follow_caught_up is LD21's (%s, not %s)"
			% [tuned, Follow.FOLLOW_CAUGHT_UP],
	)
	t.expect_eq(Follow.asked(w, m), 0, "the follower asked Von nothing")
