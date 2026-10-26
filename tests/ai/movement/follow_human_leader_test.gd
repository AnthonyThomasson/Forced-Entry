extends GameTest
## LD19 and LD21: a human leader gets the same rule. A puppet stands in for the human leader of a
## squad of two invader NPCs, built and bound the way a match builds it with "Lead the team" on (the
## human handed to `Squad.setup` as `human`, `MatchBuilder.bind_squad`). The human walks a route
## along the back garden north of the Terrace house, west, and stops facing west. The NPCs follow
## it in a file on its trail while it walks (each spot `FOLLOW_GAP` + `FOLLOW_STEP` x its place
## behind the human, the walk re-aimed only once the spot has moved `FOLLOW_RETARGET`), and once it
## has stood `FOLLOW_STILL_TIME` they take spots on a ring round it (`FOLLOW_RING` 80 px), behind
## its facing, and face outward. Mid-walk the squad's `view()` (what the leader overlay draws,
## LD28) holds the trail, the leash and each member's own follow spot, its place in the file behind
## the human.
##
## Real Von, the whole pipeline; no switch. The house is the bare Terrace house, so there is a house
## to search: left to themselves the NPCs go in and search it.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## The human's route: along the garden north of the house (its north wall is y 0), westward.
const ROUTE := [Vector2(700, -80), Vector2(400, -80), Vector2(150, -80)]
## Where the human looks once it stops: on west along the garden.
const LOOK := Vector2(-200, -80)
## How long (s) the followers have to take their ring spots once the human stands still.
const RING_WITHIN := 6.0
## How far (px) off the ring's radius a follower may stand (a snapped spot, a body's give).
const RING_SLACK := 35.0
## How far (px) a follower's spot may lie off its place in the file, at the median over the walk
## (the trail's `TRAIL_STEP` points, a snapped spot).
const FILE_SLACK := 15.0
## Where (x) on the second leg the squad's view is read: 100 px into the leg, the file behind the
## human on one straight line.
const VIEW_AT_X := 600.0


func describe() -> Dictionary:
	return {
		"name": "Members follow a human leader and ring it when it stops",
		"description": "A puppet human leader walks a route along the garden: its two NPC "
			+ "teammates follow it in a file, and ring it behind its facing, facing out, once it "
			+ "stops.",
		"tags": ["ai", "movement", "squad", "follow", "leadership", "human", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", Vector2(900, -80), { "movement:aim_point": Vector2(700, -80) })
	s.actor(&"m1", &"invader", Vector2(960, -40))
	s.actor(&"m2", &"invader", Vector2(975, -120))
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad: Node = t.world.squad(&"invader")
	var me := t.actor(&"me")
	var members := _members(t, squad, me)
	if members.is_empty():
		return
	await t.seconds(1.5)
	var nodes: Array = [me] + members
	var w := FollowWatch.new_watch()
	# Per follower: how far its spot lies behind the human on the straight legs (`spacing`), and how
	# far each re-aim of its walk moved where it was going (`reaims`, from `aimed`); `viewed` is
	# `squad.view()` mid-walk, with where the human stood then.
	var rec := { "spacing": {}, "reaims": {}, "aimed": {}, "viewed": {} }
	await _walk_route(t, squad, nodes, w, rec)
	await _stand(t, squad, nodes, w, rec)

	_check_ring(t, me, members, w, float(rec["stopped_at"]))
	_check_file(t, members, rec)
	t.check(rec["rang"], "both rang the human within %.1f s of its standing still" % RING_WITHIN)
	_check_tunables(t)
	_check_view(t, members, rec["viewed"])
	t.check(
		members.all(func(m): return FollowWatch.asked(w, m) == 0),
		"the followers asked Von nothing (%s)"
			% str(members.map(func(m): return FollowWatch.asked(w, m))),
	)


## The two NPC teammates, once the human leads and both follow it; empty when a premise fails.
func _members(t: TestContext, squad: Node, me: Node) -> Array:
	if not t.require(squad.leader() == me, "the human leads (premise: Lead the team)"):
		return []
	var members: Array = [t.actor(&"m1"), t.actor(&"m2")]
	if not t.require(
			members.all(func(m): return squad.follows(m)),
			"premise: both NPCs follow the human (Squad.follows)",
	):
		return []
	return members


## The human walks `ROUTE`, the team sampled into `w` and `rec` every frame.
func _walk_route(t: TestContext, squad: Node, nodes: Array, w: Dictionary, rec: Dictionary) -> void:
	var me: Node = nodes[0]
	var members: Array = nodes.slice(1)
	var puppet := t.puppet(&"me")
	for m: Node in members:
		rec["spacing"][m] = []
		rec["reaims"][m] = []
	for leg in ROUTE.size():
		var point: Vector2 = ROUTE[leg]
		puppet.aim_at(point)
		puppet.walk_to(point)
		while not puppet.has_arrived() and t.time < 60.0:
			FollowWatch.tick(w, t, nodes, squad)
			if leg == 1 and rec["viewed"].is_empty() and me.global_position.x <= VIEW_AT_X:
				rec["viewed"] = { "view": squad.view(), "lead": me.global_position }
			for m: Node in members:
				_sample(squad, me, m, leg, rec)
			await t.frames(1)


## Follower `m`'s sample on leg `leg` into `rec`: its spot's distance behind the human past the
## first leg, and the move of where its walk goes when it re-aims.
func _sample(squad: Node, me: Node, m: Node, leg: int, rec: Dictionary) -> void:
	if leg > 0:
		rec["spacing"][m].append(squad.follow_spot(m).distance_to(me.global_position))
	var to := Follow.walk_target(m)
	var aimed: Dictionary = rec["aimed"]
	if Follow.following(m) and to != Vector2.INF:
		if aimed.has(m) and to.distance_to(aimed[m]) > 0.0:
			rec["reaims"][m].append(to.distance_to(aimed[m]))
		aimed[m] = to


## The human stops and looks along `LOOK`; into `rec`: when it stopped (`stopped_at`), the walk's
## record (`walked`) and whether both followers rang it within `RING_WITHIN` (`rang`).
func _stand(t: TestContext, squad: Node, nodes: Array, w: Dictionary, rec: Dictionary) -> void:
	var me: Node = nodes[0]
	var members: Array = nodes.slice(1)
	var puppet := t.puppet(&"me")
	puppet.stop()
	puppet.aim_at(LOOK)
	var stopped_at := t.time
	var walked := FollowWatch.new_watch()
	walked["samples"] = w["samples"].duplicate()
	var ringed := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return members.all(func(m): return _on_ring(me, m))
	# The ring is laid once the human has stood `FOLLOW_STILL_TIME` (LD21): a file that halts within
	# the ring's band is not on it yet.
	var still := func() -> bool:
		FollowWatch.tick(w, t, nodes, squad)
		return t.time - stopped_at >= Follow.FOLLOW_STILL_TIME
	await t.until(still, Follow.FOLLOW_STILL_TIME + 1.0)
	var rang := await t.until(ringed, RING_WITHIN)
	await t.seconds(1.0)
	rec.merge({ "stopped_at": stopped_at, "walked": walked, "rang": rang }, true)


## Each follower follows, and stands on the ring round the human, behind its facing, facing out.
func _check_ring(
		t: TestContext,
		me: Node,
		members: Array,
		w: Dictionary,
		stopped_at: float,
) -> void:
	for m: Node in members:
		t.check(
			FollowWatch.took(w, m, "follow"),
			"%s follows the human (FOLLOW; acts %s)" % [m.name, FollowWatch.acts_of(w, m)],
		)
		var off: Vector2 = m.global_position - me.global_position
		var facing: Vector2 = (LOOK - me.global_position).normalized()
		t.check(
			_on_ring(me, m),
			"%s stands on the ring round the human (%.0f px off it, ring %.0f +- %.0f; %.1f s on)"
				% [m.name, off.length(), Follow.FOLLOW_RING, RING_SLACK, t.time - stopped_at],
		)
		t.check(
			off.dot(facing) < 0.0,
			"%s stands behind the human's facing (offset %s, facing %s)"
				% [m.name, str(off.round()), str(facing)],
		)
		t.check(
			(m.get("facing") as Vector2).dot(off.normalized()) > 0.5,
			"%s faces outward from the human (facing %s, offset %s)"
				% [m.name, str(m.get("facing")), str(off.round())],
		)


## Over the walk each follower kept within a band of the human, its spot at its place in the file,
## and re-aimed its walk only once its spot had moved `FOLLOW_RETARGET`.
func _check_file(t: TestContext, members: Array, rec: Dictionary) -> void:
	var walked: Dictionary = rec["walked"]
	var spacing: Dictionary = rec["spacing"]
	var reaims: Dictionary = rec["reaims"]
	for i in members.size():
		var m: Node = members[i]
		var gaps := FollowWatch.gaps(walked, m, 2.5)
		var band := FollowWatch.percentile(gaps, 0.5)
		var p90 := FollowWatch.percentile(gaps, 0.9)
		t.check(
			band <= Follow.band_p50(i) and p90 <= Follow.BAND_P90,
			"%s walks within a band of the human (p50 %.0f px, most %.0f; p90 %.0f, most %.0f)"
				% [m.name, band, Follow.band_p50(i), p90, Follow.BAND_P90],
		)
		var behind := Follow.FOLLOW_GAP + Follow.FOLLOW_STEP * i
		var p50 := FollowWatch.percentile(spacing[m], 0.5)
		t.check(
			absf(p50 - behind) <= FILE_SLACK,
			"%s's spot keeps %.0f px behind the walking human, follower %d of the file (median "
				% [m.name, behind, i + 1]
				+ "%.0f px, within %.0f; %d samples)" % [p50, FILE_SLACK, spacing[m].size()],
		)
		var least: float = reaims[m].min() if not reaims[m].is_empty() else INF
		t.check(
			reaims[m].size() >= 3 and least >= Follow.FOLLOW_RETARGET - 1.0,
			"%s re-aims its walk only once its spot moved %.0f px (%d re-aims, the least %.1f px)"
				% [m.name, Follow.FOLLOW_RETARGET, reaims[m].size(), least],
		)


## The squads' follow tunables (`SquadFollowConfig`) are the spec's.
func _check_tunables(t: TestContext) -> void:
	var tuned := {
		"gap": Follow.FOLLOW_GAP, "step": Follow.FOLLOW_STEP,
		"ring": Follow.FOLLOW_RING, "still_time": Follow.FOLLOW_STILL_TIME,
		"retarget": Follow.FOLLOW_RETARGET, "arrive": Follow.FOLLOW_ARRIVE,
		"leash": Follow.LEASH, "leash_break": Follow.LEASH_BREAK,
	}
	var holder: Script = SquadFollowConfig
	var off_spec: Array = tuned.keys().filter(
		func(k): return not is_equal_approx(float(holder.get(k)), float(tuned[k])),
	)
	t.check(
		off_spec.is_empty(),
		"the squad's follow tunables are LD21 to LD23's (off: %s)"
			% str(off_spec.map(func(k): return "%s %s, not %s" % [k, holder.get(k), tuned[k]])),
	)


## The squad's view read mid-walk (`viewed`) holds the trail and the leash, and each member's row
## its own follow spot in the file.
func _check_view(t: TestContext, members: Array, viewed: Dictionary) -> void:
	var view: Dictionary = viewed.get("view", {})
	var rows: Array = view.get("members", [])
	var trail: Array = view.get("trail", [])
	t.check(
		trail.size() >= 2 and is_equal_approx(float(view.get("leash", 0.0)), Follow.LEASH),
		"mid-walk the view holds the human's trail and the leash (%d trail points, leash %s)"
			% [trail.size(), str(view.get("leash"))],
	)
	var lead: Vector2 = viewed.get("lead", Vector2.INF)
	var off_file: Array = members.filter(func(m):
		var row: Array = rows.filter(func(r): return r["node"] == m)
		var behind := Follow.FOLLOW_GAP + Follow.FOLLOW_STEP * members.find(m)
		if row.size() != 1:
			return true
		return absf((row[0]["follow_spot"] as Vector2).distance_to(lead) - behind) > FILE_SLACK)
	t.check(
		not rows.is_empty() and off_file.is_empty(),
		"each member's view row carries its own follow spot, its place in the file behind the "
			+ "human (human at %s; rows %s)"
			% [
				str(lead.round()),
				str(rows.map(func(r): return [Follow.name_of(r["node"]), r["follow_spot"]])),
			],
	)


## Whether `m` stands on the ring round `lead` (`FOLLOW_RING` px, within `RING_SLACK`).
func _on_ring(lead: Node, m: Node) -> bool:
	var d: float = m.global_position.distance_to(lead.global_position)
	return absf(d - Follow.FOLLOW_RING) <= RING_SLACK
