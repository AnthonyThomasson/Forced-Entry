extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR14): the pie is a look through the
## doorway, so a doorway whose standing door shuts the view (a shut hollow door) has none to slice:
## the point stays in its slot until the stack is ready, then crosses, opening the door on its way
## in (DR14). Two invaders stack on the kitchen's shut back door; neither slices the pie (no
## step of it walked, nothing of the room seen), the point radios going in, the door is opened
## fully and both go into the kitchen.

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
		"name": "Entry skips the pie at a shut door",
		"description": "Two invaders stack at the kitchen's shut hollow back door: the point does "
			+ "not slice the pie, crosses once the stack is ready, opens the door and both go in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false, {
		"name": "back_door", "material": "hollow", "style": "flush",
		"hinge": HINGE, "swing_into": Vector2.LEFT,
	})
	Entry.rules(s, DOOR)
	Entry.npc(s, &"a", Vector2(960, 60))
	Entry.npc(s, &"b", Vector2(985, 110), { "tuning:decision:decide_interval": 0.55 })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var seen := { "sliced": false, "both_in": false }
	var door_shut_at_start: bool = door.angle() <= 1.0
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
	if not t.require(door_shut_at_start, "premise: the door starts shut"):
		return
	if not t.require(
			not Entry.calls(t, "going_in").is_empty(),
			"premise: the point radioed it was going in (acts %s, %s)" % [
				Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act(),
			],
	):
		return
	t.check(not seen["sliced"], "neither invader sliced the pie at a door that shuts the view")
	t.check(door.angle() >= OPEN, "the door was opened fully (%.0f degrees)" % door.angle())
	t.check(seen["both_in"], "both invaders went into the kitchen")
