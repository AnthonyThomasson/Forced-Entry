extends GameTest
## Issue #95 (rule 11), one mechanism: an NPC gives way to a walker only on the stretch its own walk
## still covers (`Locomotion`: its course is reckoned until the end of its walk, at most
## `GIVE_HORIZON`). An invader NPC follows a still puppet leader to its ring spot behind it; a
## second puppet walks across the NPC's line just past that spot, facing away so it cannot see the
## NPC (the NPC never has the right of way over it). The NPC's walk ends short of that walker's
## course, so it walks on to its spot without giving way. Then the leader stands far down the hall:
## the NPC's walk to its new spot passes through the walker's course, crossed again in front of it,
## and it gives way as before.
##
## Real Von, the whole pipeline; the leader and the walker are puppets moved by the test (the leader
## put down at its second place, the walker at the start of each crossing). Nobody is hostile.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const HALL := Rect2(0, 0, 2000, 900)
## The leader faces north, so its ring spots lie south of it, on the NPC's line from the west.
const LEAD_AT := Vector2(700, 450)
const LEAD_THEN := Vector2(1500, 450)
const NPC_AT := Vector2(100, 520)
## Where the walker waits between crossings: out of everyone's way.
const PARKED := Vector2(1000, 850)
## How far (px) past the NPC's spot, along its walk, the walker's first course crosses its line:
## past `GIVE_CLEARANCE` (36 px) and short of the leader.
const PAST_SPOT := 55.0
## Where (x) the walker's second course crosses the NPC's line: midway down its walk.
const MID_X := 1100.0
## How far (px) off the NPC's line each crossing starts, and ends on the other side.
const CROSS_FROM := 150.0
const CROSS_TO := 250.0
## The NPC's distance (px) to the walker's course when the crossing starts: the walker reaches
## the NPC's line about as the NPC would.
const TRIGGER := 230.0
## How long (s) each phase is watched at most.
const PHASE_S := 8.0


func describe() -> Dictionary:
	return {
		"name": "An NPC does not give way to a walker its walk stops short of",
		"description": "A follower walks to its spot behind a still leader while a walker crosses "
			+ "just past that spot: it walks on without giving way; on a walk that passes through "
			+ "the walker's course it still gives way.",
		"tags": ["ai", "movement", "navigation", "squad", "follow", "von"],
		"requires_von": true,
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	s.actor(&"lead", &"puppet", LEAD_AT, _tough(LEAD_AT + Vector2.UP * 300))
	s.actor(&"m", &"invader", NPC_AT)
	s.actor(&"walker", &"puppet", PARKED, _tough(PARKED + Vector2.RIGHT * 300))
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var lead := t.actor(&"lead")
	var m := t.actor(&"m")
	if not t.require(
			squad.leader() == lead and squad.follows(m),
			"premise: the puppet leads and the NPC follows it",
	):
		return
	var short := await _phase(t, squad, m, func(spot: Vector2): return spot.x + PAST_SPOT)
	if not t.require(
			short["crossed"],
			"premise: the walker crossed the NPC's line %.0f px past its spot while it walked "
				% PAST_SPOT
				+ "(%s)" % short,
	):
		return
	t.check(
		not short["gave_way"],
		"the NPC walked on to its spot without giving way to a walker its walk stopped short of "
			+ "(%s)" % short,
	)
	lead.global_position = LEAD_THEN
	var passing := await _phase(t, squad, m, func(_spot: Vector2): return MID_X)
	if not t.require(
			passing["crossed"],
			"premise: the walker crossed the NPC's line at x %.0f ahead of it while it walked (%s)"
				% [MID_X, passing],
	):
		return
	t.check(
		passing["gave_way"],
		"the NPC gave way to the walker crossing the walk it was on (%s)" % passing,
	)


## One crossing: once the NPC is `TRIGGER` px from the course at x `course_x.call(spot)` (its live
## follow spot), the walker walks across its line there, facing east (away from it). Returns
## `{ crossed, gave_way, arrived }`: whether the walker crossed the line while the NPC was still
## walking toward it, whether the NPC gave way from then on, and whether it reached its spot.
func _phase(t: TestContext, squad: Node, m: Node, course_x: Callable) -> Dictionary:
	var walker := t.actor(&"walker")
	var puppet := t.puppet(&"walker")
	var out := { "crossed": false, "gave_way": false, "arrived": false }
	var x := INF
	var end := t.time + PHASE_S
	while t.time < end:
		var spot: Vector2 = squad.follow_spot(m)
		var here: Vector2 = m.global_position
		if x == INF and spot != Vector2.INF and absf(course_x.call(spot) - here.x) <= TRIGGER:
			x = course_x.call(spot)
			walker.global_position = Vector2(x, spot.y - CROSS_FROM)
			puppet.aim_at(walker.global_position + Vector2.RIGHT * 300)
			puppet.walk_to(Vector2(x, spot.y + CROSS_TO))
		if x != INF:
			var loco: Dictionary = Follow.brain_of(m).debug_state().get("loco", {})
			out["gave_way"] = out["gave_way"] or bool(loco.get("giving_way", false))
			if absf(walker.global_position.y - here.y) < 10.0 and here.x < x:
				out["crossed"] = true
			out["arrived"] = here.distance_to(spot) <= Follow.FOLLOW_ARRIVE + 2.0
			if out["arrived"] and puppet.has_arrived():
				break
		await t.frames(1)
	out["at"] = m.global_position.round()
	puppet.stop()
	walker.global_position = PARKED
	await t.frames(1)
	return out


## A puppet on the invaders' side that cannot die, looking at `aim`.
func _tough(aim: Vector2) -> Dictionary:
	return { "faction": &"invader", "max_health": 1_000_000.0, "movement:aim_point": aim }
