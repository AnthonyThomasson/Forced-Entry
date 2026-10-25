extends GameTest
## LD22: a follower at rest at its spot, with no fight, tops up a low magazine (not only a dry one)
## without asking Von. A puppet stands in for the human leader of a squad of one invader NPC, built
## and bound as Main builds it; the leader stands still in the back garden north of the Terrace
## house, facing west. The NPC starts some way off with a pistol part-spent: it follows, takes its
## spot on the ring round the still leader, and there, at rest, reloads (a `reload` start from it)
## while its decision walks put no question to Von.
##
## Real Von, the whole pipeline; no switch. The premise is the part-spent magazine (`start_rounds`
## 2 of the pistol's, with its default spares), on the bare Terrace house.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const LEAD_AT := Vector2(300, -80)
## Where the follower starts: east along the garden, out of the ring.
const START := Vector2(800, -90)
## How long (s) the follower has to reach its spot and top up.
const WITHIN := 20.0
## How far (px) a follower at rest may have moved in the half second before its reload began.
const REST_DRIFT := 12.0


func describe() -> Dictionary:
	return {
		"name": "A follower at rest tops up a low magazine without asking Von",
		"description": "An invader following a still human leader with a part-spent pistol reaches "
			+ "its spot on the ring and reloads there, with no Von request.",
		"tags": ["ai", "movement", "squad", "follow", "reload", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Stack.human(s, &"me", LEAD_AT, { "aim_point": Vector2(-200, -80) })
	# Premise: a part-spent magazine (2 rounds), the default spares to top up from.
	s.actor(&"m", &"invader", START, { "start_slot": 3, "start_rounds": 2 })
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	if not t.require(squad.follows(m), "premise: the NPC follows the human (Squad.follows)"):
		return
	if not t.require(
			m.ammo.rounds() > 0 and m.ammo.rounds() < m.ammo.capacity(3)
				and m.ammo.spare_magazines() > 0,
			"premise: a part-spent pistol with spares (%d of %d, %d spares)"
				% [m.ammo.rounds(), m.ammo.capacity(3), m.ammo.spare_magazines()],
	):
		return
	var trail: Array = []  # [time, position] of the follower, for its rest before the reload
	var reloaded := func() -> bool:
		trail.append([t.time, m.global_position])
		return not _reloads(t, m).is_empty()
	var w: Dictionary = await Follow.watch(
		t,
		[me, m],
		squad,
		WITHIN,
		{ "stop": func(_rec: Dictionary) -> bool: return reloaded.call() },
	)

	t.check(
		Follow.took(w, m, "follow"),
		"the NPC follows its leader (FOLLOW; acts %s)" % Follow.acts_of(w, m),
	)
	var starts := _reloads(t, m)
	if not t.check(
			not starts.is_empty(),
			"the follower topped up its magazine within %.0f s (acts %s)"
				% [WITHIN, Follow.acts_of(w, m)],
	):
		return
	var at: float = starts[0]["time"]
	var where := _at(trail, at)
	t.check(
		absf(where.distance_to(me.global_position) - Follow.FOLLOW_RING) <= 40.0,
		"it reloaded at its spot on the ring round the leader (%.0f px from it)"
			% where.distance_to(me.global_position),
	)
	t.check(
		_at(trail, at - 0.5).distance_to(where) <= REST_DRIFT,
		"at rest: it had stood still for the half second before (moved %.0f px)"
			% _at(trail, at - 0.5).distance_to(where),
	)
	t.expect_eq(Follow.asked(w, m), 0, "it asked Von nothing (acts %s)" % Follow.acts_of(w, m))


## The raw `reload` start events (`{ topic, data, time }`) of character `c`.
func _reloads(t: TestContext, c: Node) -> Array:
	return t.events.filter(func(e): return (
		e["topic"] == &"reload"
			and e["data"].get("character") == c
			and e["data"].get("stage") == &"start"
	))


## Where `trail` (`[[time, position]]`) has the follower at sim time `at` (the last sample at or
## before it).
func _at(trail: Array, at: float) -> Vector2:
	var p := Vector2.INF
	for pair in trail:
		if float(pair[0]) <= at:
			p = pair[1]
	return p
