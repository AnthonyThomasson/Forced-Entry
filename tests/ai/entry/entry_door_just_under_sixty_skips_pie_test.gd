extends GameTest
## Desired (E3, the interim rule until #159; `docs/doors.md` DR14): a door open to just under 60
## degrees, the spec's edge, still opens less than the doorway's width and shuts the view, so the
## pie is not sliced: the invader crosses once the stack is ready and goes in. The partner of
## `entry_door_just_over_sixty_keeps_pie`, which is open just past the edge.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")
const AJAR := 59.0


func describe() -> Dictionary:
	return {
		"name": "Entry skips the pie at a door open to just under 60 degrees",
		"description": "An invader at the kitchen's back door, open 59 degrees: it does not "
			+ "slice the pie, crosses once ready and goes in.",
		"tags": ["ai", "entry", "scripted", "door"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s, { "angle": AJAR })
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door: Node = t.object(&"back_door")
	var door_ajar_at_start: bool = is_equal_approx(door.angle(), AJAR)
	var seen := { "sliced": false }
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
	t.check(not seen["sliced"], "the invader did not slice the pie at a door open to 59 degrees")
	t.check(got_in, "and went into the kitchen")
