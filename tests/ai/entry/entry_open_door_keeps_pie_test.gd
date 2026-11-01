extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR14): a door open wide enough to pass
## does not shut the view, so the pie is sliced at it as at a bare doorway: the point walks the arc,
## sees into the kitchen past the open leaf from outside, then crosses. The rule that skips the pie
## at a door that shuts the view (`entry_shut_door_skips_pie`) leaves it alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## The kitchen's back doorway with a 60 px door in it, framed from outside.
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
## The leaf stands open to its limit within this many degrees.
const OPEN := 88.0


func describe() -> Dictionary:
	return {
		"name": "Entry slices the pie at an open door",
		"description": "An invader at the kitchen's fully open hollow back door slices the pie, "
			+ "seeing into the kitchen past the leaf, then goes in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false, {
		"name": "back_door", "material": "hollow", "style": "flush",
		"hinge": HINGE, "swing_into": Vector2.LEFT, "angle": 90.0,
	})
	Entry.rules(s, DOOR)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var seen := { "sliced": false, "most": 0.0, "open_while_slicing": false }
	var in_kitchen := func() -> bool:
		var e := Entry.entry(Entry.brain(t, &"inv"))
		if e.get("phase") == "pie":
			seen["sliced"] = true
			seen["most"] = maxf(seen["most"], float(e.get("seen_fraction", 0.0)))
			seen["open_while_slicing"] = door.angle() >= OPEN
		return Entry.in_room(DOOR, t.actor(&"inv").global_position)
	await t.until(in_kitchen, 50.0)
	if not t.require(
			not Entry.calls(t, "going_in", &"inv").is_empty(),
			"premise: the invader radioed it was going in (act %s)"
				% Entry.brain(t, &"inv").current_act(),
	):
		return
	t.check(seen["sliced"], "the invader sliced the pie at the open door")
	t.check(seen["open_while_slicing"], "the door stood fully open while it sliced")
	t.check(
		seen["most"] >= 0.5,
		"it saw at least half the kitchen from outside (%.2f)" % seen["most"],
	)
