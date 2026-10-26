extends GameTest
## LD23's break: a fighting follower left more than `LEASH_BREAK` (1.3) leashes from its leader
## re-decides (and with no COMBAT option left within the leash it follows, FOLLOW, firing at what it
## sees on the way); either way its fight comes back within the leash. A puppet stands in for the
## human leader of a squad of one invader NPC (bound as Main binds it), in an open hall; the NPC
## fights a household target in plain sight. Then the leader runs away down the hall, far past 1.3
## leashes. The NPC walks back to it: it comes within the leash of its leader again.
##
## Real Von, the whole pipeline; no switch. Premises: the target and the leader are never killed
## (`max_health`), and the target, a puppet, never shoots.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const HALL := Rect2(0, 0, 1700, 900)
const LEAD_AT := Vector2(900, 450)
const NPC_AT := Vector2(950, 510)
const TARGET_AT := Vector2(1250, 450)
## Where the leader runs to: 650 px west, past 1.3 leashes (416 px) from where the NPC fights.
const LEAD_TO := Vector2(250, 450)
## How long (s) the NPC has, once the leader stands at `LEAD_TO`, to come back within the leash.
const BACK_WITHIN := 12.0


func describe() -> Dictionary:
	return {
		"name": "A member left behind in a fight walks back to its leader",
		"description": "An invader fights a target while its human leader runs off down the hall: "
			+ "past 1.3 leashes it breaks off and comes back within the leash of the leader.",
		"tags": ["ai", "combat", "squad", "leash", "follow", "leadership", "von"],
		"requires_von": true,
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	Stack.human(s, &"me", LEAD_AT, { "movement:aim_point": TARGET_AT })
	s.actor(&"m", &"invader", NPC_AT, { "max_health": 1_000_000.0 })
	s.actor(
		&"target",
		&"puppet",
		TARGET_AT,
		{
			"faction": &"household",
			"max_health": 1_000_000.0,
			"movement:aim_point": NPC_AT,
			"facing": Vector2.LEFT,
		},
	)
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(
			await t.until(func(): return Follow.act(m).begins_with("combat"), 10.0),
			"the NPC fights the target in sight (act %s)" % Follow.act(m),
	):
		return
	var w := FollowWatch.new_watch()
	var broke_at := await _left_behind(t, w, squad, me, m)
	if broke_at < 0.0:
		return
	var back := func() -> bool:
		FollowWatch.tick(w, t, [me, m], squad)
		t.trace("from leader", m.global_position.distance_to(me.global_position))
		return m.global_position.distance_to(me.global_position) <= Follow.LEASH
	t.check(
		await t.until(back, BACK_WITHIN),
		"the NPC walked back within the leash of its leader within %.0f s (%.0f px off; acts %s)"
			% [
				BACK_WITHIN,
				m.global_position.distance_to(me.global_position),
				FollowWatch.acts_of(w, m),
			],
	)
	_check_refollowed(t, w, m, broke_at)


func _left_behind(t: TestContext, w: Dictionary, squad: Node, me: Node, m: Node) -> float:
	var lead := t.puppet(&"me")
	lead.aim_at(LEAD_TO)
	# The leader runs: LD23 keeps the fighter's spots within the leash of the leader's live
	# position, so behind a walking leader they trail it short of the break (414 px at most against
	# 416); only a leader outpacing the fighter leaves it past 1.3 leashes.
	lead.set_run(true)
	lead.walk_to(LEAD_TO)
	# The distance is sampled during the walk, not once the leader has arrived: the break starts
	# acting as soon as the NPC is past the break, so by the leader's arrival it may already be
	# walking back. `broke_at` is when it first was past the break, which its re-decision follows.
	var brk := Follow.LEASH * Follow.LEASH_BREAK
	var left := [0.0]
	var broke_at := [INF]
	var walked := func() -> bool:
		FollowWatch.tick(w, t, [me, m], squad)
		var d: float = m.global_position.distance_to(me.global_position)
		left[0] = maxf(left[0], d)
		if d > brk and broke_at[0] == INF:
			broke_at[0] = t.time
		return lead.has_arrived()
	if not t.require(await t.until(walked, 10.0), "the leader ran off to %s" % str(LEAD_TO)):
		return -1.0
	if not t.require(
			left[0] > brk,
			"premise: the NPC was left past 1.3 leashes during the walk (%.0f px, break %.0f)"
				% [left[0], brk],
	):
		return -1.0
	return broke_at[0]


func _check_refollowed(t: TestContext, w: Dictionary, m: Node, broke_at: float) -> void:
	var refollowed := (w["acts"].get(m, []) as Array).any(
		func(p): return float(p[0]) >= broke_at and String(p[1]).begins_with("follow"),
	)
	t.check(
		refollowed,
		"past the break (at %.1f s) the NPC re-decided and took FOLLOW (acts %s)"
			% [broke_at, FollowWatch.acts_of(w, m)],
	)
