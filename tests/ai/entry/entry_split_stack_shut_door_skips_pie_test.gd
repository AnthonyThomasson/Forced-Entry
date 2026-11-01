extends GameTest
## Desired (E3, E19, the interim rule until #159; `docs/doors.md` DR14): a split stack at a shut
## door. Two invaders come at the kitchen's back door from opposite sides of the garden, one north
## of it and one south, so each stacks on its own side. The point does not slice the pie at a door
## that shuts the view, and the other side's front man, who would slice his own half at a bare
## doorway, does not either: he waits for the point and follows it in.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")
const IDS := [&"north", &"south"]


func describe() -> Dictionary:
	return {
		"name": "A split stack slices no pie at a shut door",
		"description": "Two invaders stack on opposite sides of the kitchen's shut back door: "
			+ "neither slices the pie, the point crosses once ready and the other follows it in.",
		"tags": ["ai", "entry", "stack", "scripted", "door"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	DoorPie.configure(s)
	Entry.npc(s, &"north", Vector2(980, -40), {}, { "facing": Vector2.LEFT })
	Entry.npc(
		s, &"south", Vector2(980, 420),
		{ "tuning:decision:decide_interval": 0.55 }, { "facing": Vector2.LEFT },
	)


func run(t: TestContext) -> void:
	var door_shut_at_start: bool = (t.object(&"back_door") as Node).angle() <= 1.0
	var seen := { "sliced": false }
	var both_in := func() -> bool:
		seen["sliced"] = seen["sliced"] or DoorPie.slicing(t, IDS)
		return IDS.all(
			func(id): return Entry.in_room(DoorPie.DOOR, t.actor(id).global_position),
		)
	var got_in: bool = await t.until(both_in, 80.0)
	if not t.require(door_shut_at_start, "premise: the door starts shut"):
		return
	var sides := IDS.map(func(id):
		var mine := Entry.calls(t, "claim", id).filter(
			func(c): return String(c.get("opening", "")) == DoorPie.DOOR["id"],
		)
		return mine.back().get("side", 0) if not mine.is_empty() else 0)
	if not t.require(
			sides[0] != 0 and sides[1] != 0 and sides[0] != sides[1],
			"premise: the stack is split, one invader on each side of the door (sides %s)"
				% str(sides),
	):
		return
	t.check(not seen["sliced"], "neither the point nor the other side's front man sliced the pie")
	t.check(got_in, "and both went into the kitchen")
