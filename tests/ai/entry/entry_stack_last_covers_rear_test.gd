extends GameTest
## E12: while the stack waits at the door, the last man faces back the way the team came and holds
## the approach, from reaching his slot until the member ahead of him goes (the point, meanwhile, is
## slicing the pie). Real Von: three invaders in the back garden decide for themselves to stack on
## the back door. The point's pie is slowed, so the last man reaches his slot while it still slices
## and the stack has a real wait for him to cover.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const EntryWatch := preload("res://tests/_ai/entry_watch_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const IDS := [&"a", &"b", &"c"]
## Seconds the point looks through the door from each step of its arc (the default is 0.35).
const PIE_DWELL := 1.0
## The shortest wait (s) in the slot the last man's facing is judged over.
const MIN_WAIT := 1.0


func describe() -> Dictionary:
	return {
		"name": "Entry stack's last man covers the rear",
		"description": "Of three invaders stacked at the back door, the last faces back along the "
			+ "wall, not the door, while he waits in his slot.",
		"tags": ["ai", "entry", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(960, 40))
	s.actor(&"b", &"invader", Vector2(985, 100))
	s.actor(&"c", &"invader", Vector2(990, 280))
	for id in IDS:
		s.set_props(id, "GoalController", { "tuning:entry:pie_dwell": PIE_DWELL })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var all_going := func():
		return IDS.all(func(id): return Entry.first_call_time(t, "going_in", id, door["id"]) < INF)
	var samples := await EntryWatch.watch(t, IDS, door, 60.0, all_going)
	var by_slot := _stack_by_slot(t, door)
	if by_slot.is_empty():
		return
	var last: StringName = by_slot[3]
	var from := Entry.first_call_time(t, "ready", last, door["id"])
	var to := Entry.first_call_time(t, "going_in", by_slot[2], door["id"])
	if not t.require(
			to - from >= MIN_WAIT,
			"the last man (%s) waits in his slot at least %.1f s before the file goes (%.2f s)"
				% [last, MIN_WAIT, to - from],
	):
		return
	var waiting := samples.filter(func(s): return s["t"] >= from and s["t"] < to)
	var away := EntryWatch.share_facing(
		waiting,
		last,
		func(
			p: Vector2,
			f: Vector2,
		): return f.dot(((door["pos"] as Vector2) - p).normalized()) <= 0.0,
	)
	t.check(
		away >= 0.6,
		"the last man (%s) faces back along the wall, away from the door, while he waits"
			% last + " (%.0f%% of %.2f s)" % [away * 100.0, to - from],
	)


## The three stacked at `door`, slot -> actor id, once each and on one side of it; {} (a failed
## requirement) when they did not.
func _stack_by_slot(t: TestContext, door: Dictionary) -> Dictionary:
	var acts := ", ".join(IDS.map(func(id): return Entry.brain(t, id).current_act()))
	for step in ["claim", "ready"]:
		if not t.require(
				IDS.all(func(id): return Entry.first_call_time(t, step, id, door["id"]) < INF),
				"all three radioed %s at the back door (%s)" % [step, acts],
		):
			return {}
	var by_slot := {}
	for id in IDS:
		by_slot[int(Entry.entry(Entry.brain(t, id)).get("slot", 0))] = id
	if not t.require(
			by_slot.has(1) and by_slot.has(2) and by_slot.has(3),
			"slots 1, 2 and 3 are taken once each (%s)" % str(by_slot),
	):
		return {}
	var sides := IDS.map(func(id): return int(Entry.calls(t, "ready", id)[0].get("side", 0)))
	if not t.require(
			sides.all(func(side): return side == sides[0]),
			"the three stack on one side of the door (%s)" % str(sides),
	):
		return {}
	return by_slot
