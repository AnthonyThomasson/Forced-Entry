extends GameTest
## Issue #131 (E6): a team pours into the room together. Four invaders stack at the kitchen's back
## door and go in: as the point radios `going_in` every follower starts its crossing too (its own
## `going_in` within `START_WITHIN` s of the point's), each walks in at its walking pace behind the
## one ahead (`in` within the time its way in takes at its walking pace, plus `SLACK` s, of the
## point's `going_in`: it never stands waiting), and they go through the doorway one at a time: no
## two in its funnel side by side.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const EntryWatch := preload("res://tests/_ai/entry_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b", &"c", &"d"]
## Most seconds a follower's `going_in` may come after the point's.
const START_WITHIN := 0.3
## Seconds on top of a member's own walk in that its `in` may take.
const SLACK := 0.5
## Two members in the funnel at once are abreast when they are closer than `ABREAST` px (two bodies)
## and less than `FILE_GAP` px apart along the doorway's axis: shoulder to shoulder, not one behind
## the other (one turning off into its corner as the next steps in is the file).
const ABREAST := 56.0
const FILE_GAP := 20.0


func describe() -> Dictionary:
	return {
		"name": "Entry team flows in together",
		"description": "Four invaders at the back door all start crossing as the point goes and "
			+ "walk in one behind the other, none waiting for the one ahead to be through.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 40), { "tuning:entry:ready_timeout": 30.0 })
	Entry.npc(
		s,
		&"b",
		Vector2(985, 100),
		{ "tuning:decision:decide_interval": 0.55, "tuning:entry:ready_timeout": 30.0 },
	)
	Entry.npc(
		s,
		&"c",
		Vector2(990, 280),
		{ "tuning:decision:decide_interval": 0.7, "tuning:entry:ready_timeout": 30.0 },
	)
	Entry.npc(
		s,
		&"d",
		Vector2(1010, 200),
		{ "tuning:decision:decide_interval": 0.65, "tuning:entry:ready_timeout": 30.0 },
	)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var all_in := func():
		return IDS.all(func(id): return not Entry.calls(t, "in", id).is_empty())
	var samples: Array = await EntryWatch.watch(t, IDS, door, 50.0, all_in)
	var acts := ", ".join(IDS.map(func(id): return Entry.brain(t, id).current_act()))
	if not t.require(all_in.call(), "all four went in (%s)" % acts):
		return
	var going := {}
	for id in IDS:
		going[id] = Entry.first_call_time(t, "going_in", id, door["id"])
	var point: StringName = IDS[0]
	for id in IDS:
		if going[id] < going[point]:
			point = id
	for id in IDS:
		if id == point:
			continue
		t.check(
			going[id] - going[point] <= START_WITHIN,
			"%s starts its crossing as the point goes (%.2f s after it)"
				% [id, going[id] - going[point]],
		)
	for id in IDS:
		var in_at := Entry.first_call_time(t, "in", id, door["id"])
		var walk: float = (_walked(samples, id, going[point], in_at)
				/ t.actor(id).movement.walk_speed())
		var took: float = in_at - going[point]
		t.check(
			took <= walk + SLACK,
			"%s is in %.2f s after the point went (its walk in %.2f s)" % [id, took, walk],
		)
	_check_single_file(t, samples, door)


## The px actor `id` walked in `samples` from `from` s to `to` s: its way in, whatever its shape.
func _walked(samples: Array, id: StringName, from: float, to: float) -> float:
	var length := 0.0
	var last := Vector2.INF
	for s in samples:
		if s["t"] < from or s["t"] > to or not s["pos"].has(id):
			continue
		if last != Vector2.INF:
			length += last.distance_to(s["pos"][id])
		last = s["pos"][id]
	return length


## No two members are in the doorway's funnel side by side at any frame.
func _check_single_file(t: TestContext, samples: Array, door: Dictionary) -> void:
	var abreast := []
	for s in samples:
		abreast = _abreast(s, door)
		if not abreast.is_empty():
			break
	t.check(
		abreast.is_empty(),
		"they go through the doorway one behind the other (%s)" % (
			"so they do" if abreast.is_empty()
			else "%s and %s %.0f px apart along it at %.2f s, at %s and %s" % abreast
		),
	)


## Two members in sample `s` both in the funnel of `door`, closer than `ABREAST` and less than
## `FILE_GAP` apart along its axis, as `[id, id, gap, time, pos, pos]`, or [] when there are none.
func _abreast(s: Dictionary, door: Dictionary) -> Array:
	var inside: Array = IDS.filter(
		func(id): return s["pos"].has(id) and Entry.in_funnel(door, s["pos"][id]),
	)
	for i in inside.size():
		for j in range(i + 1, inside.size()):
			var gap := absf(Entry.outward(door, s["pos"][inside[i]])
					- Entry.outward(door, s["pos"][inside[j]]))
			var apart: float = s["pos"][inside[i]].distance_to(s["pos"][inside[j]])
			if gap < FILE_GAP and apart < ABREAST:
				return [
					inside[i],
					inside[j],
					gap,
					s["t"],
					s["pos"][inside[i]].round(),
					s["pos"][inside[j]].round(),
				]
	return []
