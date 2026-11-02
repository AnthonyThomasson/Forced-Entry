extends GameTest
## Issue #183 (`docs/tactical-entry.md` E5, E3): two invaders entering the kitchen by its back door
## while the door is shut take opposite corners, as at a bare doorway. A shut door skips the pie
## (E3, `docs/doors.md` DR14), so the point goes from its slot straight to the crossing; it still
## enters as one of a team of two, not alone: the point turns to the near corner on its own side and
## the second crosses to the corner on the other side of the door.
##
## The Terrace house's back doorway with its 60 px hollow door, shut
## (`tests/_ai/entry_door_probe.gd`), and the two invaders of `entry_pair_take_opposite_corners`;
## scripted Von.

const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const EntryWatch := preload("res://tests/_ai/entry_watch_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry pair at a shut door takes opposite corners",
		"description": "Two invaders entering the kitchen by its shut back door stop at the two "
			+ "door-wall corners, one either side of the door.",
		"tags": ["ai", "entry", "door", "scripted", "callout"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s)
	Entry.npc(s, &"a", Vector2(960, 60))
	Entry.npc(s, &"b", Vector2(985, 110), { "tuning:decision:decide_interval": 0.55 })


func run(t: TestContext) -> void:
	var door := DoorPie.DOOR
	if not t.require(
			t.object(&"back_door").gap() < 1.0,
			"the back door starts shut (gap %.0f px)" % t.object(&"back_door").gap(),
	):
		return
	var stops := {}
	var samples := await EntryWatch.watch(t, [&"a", &"b"], door, 45.0, func():
		if Entry.calls(t, "in", &"a").is_empty() or Entry.calls(t, "in", &"b").is_empty():
			return false
		var last_in := maxf(
			Entry.first_call_time(t, "in", &"a"),
			Entry.first_call_time(t, "in", &"b"),
		)
		return t.time - last_in > 3.0)
	for id in [&"a", &"b"]:
		stops[id] = EntryWatch.first_stop_in_room(samples, id, door)
	if not t.require(
			stops.values().all(func(p): return p != Vector2.INF),
			"both went in and stopped at a corner (%s)" % str(stops),
	):
		return
	var la := Entry.lateral(door, stops[&"a"])
	var lb := Entry.lateral(door, stops[&"b"])
	t.check(
		signf(la) != signf(lb),
		"they took opposite sides of the door (%s / %s)"
			% [stops[&"a"].round(), stops[&"b"].round()],
	)
	for id in stops:
		t.check(
			Entry.outward(door, stops[id]) > -130.0
				and absf(Entry.lateral(door, stops[id])) > float(door["width"]) * 0.5,
			"%s stopped in a corner on the door's wall (%s)" % [id, stops[id].round()],
		)
