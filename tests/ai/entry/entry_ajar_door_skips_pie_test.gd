extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR14): a door that stands ajar, wide
## enough to walk through but not open all the way across its doorway (45 degrees), still blocks the
## view through it, so the pie is not sliced there either: the point crosses once the stack is
## ready, the AI leaving the door as it is (it is open wide enough to pass). Two invaders stack on
## the kitchen's back door and both go in without slicing the pie.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## The kitchen's back doorway with a 60 px door in it, framed from outside (`Entry.BACK` is 90 px).
const DOOR := {
	"id": "door_840_190",
	"pos": Maps.DOOR_BACK,
	"width": 60.0,
	"out": Vector2.RIGHT,
	"room": Maps.HOUSE_KITCHEN,
	"room_key": "kitchen",
}
## The hinge sits on the north jamb, 24 px from the doorway's middle, and the leaf swings into the
## kitchen.
const HINGE := Vector2(840, 166)
## The leaf is open to its limit within this many degrees.
const OPEN := 88.0


func describe() -> Dictionary:
	return {
		"name": "Entry skips the pie at an ajar door",
		"description": "Two invaders stack at the kitchen's back door, ajar at 45 degrees: the "
			+ "point does not slice the pie, crosses once the stack is ready and both go in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false, {
		"name": "back_door", "material": "hollow", "style": "flush",
		"hinge": HINGE, "swing_into": Vector2.LEFT, "angle": 45.0,
	})
	Entry.rules(s, DOOR)
	Entry.npc(s, &"a", Vector2(960, 60))
	Entry.npc(s, &"b", Vector2(985, 110), { "tuning:decision:decide_interval": 0.55 })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var seen := { "sliced": false, "both_in": false }
	var door_ajar_at_start: bool = is_equal_approx(door.angle(), 45.0)
	var both_in := func() -> bool:
		for id in [&"a", &"b"]:
			var e := Entry.entry(Entry.brain(t, id))
			if e.get("phase") == "pie" or int(e.get("pie_sides", 0)) > 0:
				seen["sliced"] = true
		seen["both_in"] = (
			Entry.in_room(DOOR, t.actor(&"a").global_position)
			and Entry.in_room(DOOR, t.actor(&"b").global_position)
		)
		return seen["both_in"]
	await t.until(both_in, 50.0)
	if not t.require(door_ajar_at_start, "premise: the door starts ajar at 45 degrees"):
		return
	if not t.require(
			not Entry.calls(t, "going_in").is_empty(),
			"premise: the point radioed it was going in (acts %s, %s)" % [
				Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act(),
			],
	):
		return
	t.check(not seen["sliced"], "neither invader sliced the pie at a door that shuts the view")
	t.check(door.angle() < OPEN, "the door was left as it was (%.0f degrees)" % door.angle())
	t.check(seen["both_in"], "both invaders went into the kitchen")
