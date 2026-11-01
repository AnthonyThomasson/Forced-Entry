extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR14): a door open to just over 60
## degrees, the spec's edge, opens as wide as the doorway and does not shut the view, so the pie is
## sliced at it as at a bare doorway: the invader walks the arc, sees into the kitchen from outside,
## then crosses. The partner of `entry_door_just_under_sixty_skips_pie`.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")
const AJAR := 61.0


func describe() -> Dictionary:
	return {
		"name": "Entry slices the pie at a door open to just over 60 degrees",
		"description": "An invader at the kitchen's back door, open 61 degrees: it slices the "
			+ "pie, seeing into the kitchen from outside, then goes in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s, { "angle": AJAR })
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var door_ajar_at_start: bool = is_equal_approx(door.angle(), AJAR)
	var seen := { "sliced": false, "most": 0.0 }
	var in_kitchen := DoorPie.entered_kitchen(t, &"inv", seen)
	var got_in: bool = await t.until(in_kitchen, 50.0)
	if not t.require(door_ajar_at_start, "premise: the door starts open to %.0f degrees" % AJAR):
		return
	if not t.require(
			not Entry.calls(t, "going_in", &"inv").is_empty(),
			"premise: the invader radioed it was going in (act %s)"
				% Entry.brain(t, &"inv").current_act(),
	):
		return
	t.check(seen["sliced"], "the invader sliced the pie at a door open to 61 degrees")
	t.check(
		seen["most"] >= 0.3,
		"it saw into the kitchen from outside (%.2f of it)" % seen["most"],
	)
	t.check(got_in, "and went into the kitchen")
