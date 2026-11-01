extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR11, DR14): a knocked-down door is
## no door: the doorway is clear, nothing shuts the view, so the pie is sliced at it as at a bare
## doorway: the invader walks the arc, sees into the kitchen from outside, then crosses. The hollow
## back door is felled before the invader arrives.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry slices the pie at a knocked-down door",
		"description": "An invader at the kitchen's back doorway, its hollow door knocked down: "
			+ "it slices the pie, seeing into the kitchen from outside, then goes in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	door.take_damage(100_000.0)
	var seen := { "sliced": false, "most": 0.0 }
	var in_kitchen := DoorPie.entered_kitchen(t, &"inv", seen)
	var got_in: bool = await t.until(in_kitchen, 50.0)
	if not t.require(door.is_down(), "premise: the door is knocked down"):
		return
	if not t.require(
			not Entry.calls(t, "going_in", &"inv").is_empty(),
			"premise: the invader radioed it was going in (act %s)"
				% Entry.brain(t, &"inv").current_act(),
	):
		return
	t.check(seen["sliced"], "the invader sliced the pie at the knocked-down door")
	t.check(
		seen["most"] >= 0.3,
		"it saw into the kitchen from outside (%.2f of it)" % seen["most"],
	)
	t.check(got_in, "and went into the kitchen")
