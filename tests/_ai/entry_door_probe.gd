extends RefCounted
## Shared set-up of the tests of the entry's pie at a door (`tests/ai/entry/entry_*_door_*`; not a
## test itself): `const DoorPie := preload("res://tests/_ai/entry_door_probe.gd")`. The kitchen's
## back doorway of the Terrace house with a 60 px hollow door in it, framed from outside, and what
## the tests read of the entry. The door's edge of 60 degrees is the spec's number
## (`docs/tactical-entry.md` E3: a door open less than the doorway's width shuts the view), not
## read from the code.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## The doorway, as `Entry.BACK` but 60 px wide: the door fills it.
const DOOR := {
	"id": "door_840_190",
	"pos": Maps.DOOR_BACK,
	"width": 60.0,
	"out": Vector2.RIGHT,
	"room": Maps.HOUSE_KITCHEN,
	"room_key": "kitchen",
}
## The hinge on the north jamb, 24 px from the doorway's middle, and the leaf swinging into the
## kitchen.
const HINGE_NORTH := Vector2(840, 166)
## The hinge on the south jamb: the gap an ajar leaf leaves is then on the north side, where the
## stack stands.
const HINGE_SOUTH := Vector2(840, 214)


## Lay out the Terrace house with the back doorway's door (`door` overrides the hollow, flush door
## hinged north, swinging west, shut) and script Von for an entry through it.
static func configure(s: TestSetup, door := {}) -> void:
	var leaf := {
		"name": "back_door", "material": "hollow", "style": "flush",
		"hinge": HINGE_NORTH, "swing_into": Vector2.LEFT,
	}
	leaf.merge(door, true)
	Maps.house(s, false, leaf)
	Entry.rules(s, DOOR)


## A check for `t.until` that notes into `seen` (`sliced`, `most`: the share of the kitchen seen
## from outside) whether invader `id` slices the pie, and is true once it stands in the kitchen.
static func entered_kitchen(t: TestContext, id: StringName, seen: Dictionary) -> Callable:
	return func() -> bool:
		if slicing(t, [id]):
			seen["sliced"] = true
			var e := Entry.entry(Entry.brain(t, id))
			seen["most"] = maxf(float(seen.get("most", 0.0)), float(e.get("seen_fraction", 0.0)))
		return Entry.in_room(DOOR, t.actor(id).global_position)


## Whether any of the actors `ids` is slicing the pie now.
static func slicing(t: TestContext, ids: Array) -> bool:
	for id: StringName in ids:
		var e := Entry.entry(Entry.brain(t, id))
		if e.get("phase") == "pie" or int(e.get("pie_sides", 0)) > 0:
			return true
	return false
