extends GameTest
## Desired: in a district match an NPC knows the furniture of the house and of no neighbour tower
## (a neighbour counts as outside for confinement, entry and spawning). A defender is familiar with
## its house: it remembers every room and every piece offering an interaction (a chair to sit on) at
## once. The pieces it may remember are the ones standing in the house's rooms; a neighbour's chair
## is not its to sit on, and scanning the whole district for pieces costs every NPC a look at each
## one all match long (perf/match_5v5_stress). So a familiar defender's memory holds the house's
## rooms and pieces and
## a handful of its own notes, not the district's several hundred pieces.

const SEED := 7
const PLAN := "garage_home"
## Notes a defender makes of its own in the first moments (the room it stands in).
const OWN_NOTES := 4


func describe() -> Dictionary:
	return {
		"name": "An NPC in a district knows the house's furniture and no neighbour's",
		"description": "A familiar defender in a district match remembers the house's rooms and "
			+ "its interactable pieces, not the pieces of the eight neighbour towers.",
		"tags": ["ai", "perception", "district", "memory"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	s.von_down()
	s.declared_match({ "defenders": { "count": 2 }, "invaders": { "count": 0 } })


func run(t: TestContext) -> void:
	var handle: Dictionary = t.world.match_handle
	var house: Node2D = handle["house"]
	var rooms: Array = handle["rooms"]
	var in_house := _interactables(house, rooms)
	var district := handle["district"] as Node2D
	var in_district := _interactables(district, [])
	if not t.require(
			in_district > in_house + OWN_NOTES * 10,
			"premise: the district has far more pieces to sit on than the house (%d, %d)"
			% [in_district, in_house],
	):
		return
	await t.seconds(1.0)
	var defenders: Array = handle["combatants"]
	for defender: Node in defenders:
		var brain := TestContext.controller_of(defender, &"debug_state")
		var known: int = brain.debug_state()["memory_size"]
		var most := rooms.size() + in_house + OWN_NOTES
		t.check(
			known >= rooms.size() + in_house,
			"%s remembers all the house's %d rooms and %d pieces (%d things)"
			% [defender.name, rooms.size(), in_house, known],
		)
		t.check(
			known <= most,
			"%s remembers %d things, at most the house's %d rooms and %d pieces and its own notes"
			% [defender.name, known, rooms.size(), in_house],
		)


## How many pieces under `root` offer an interaction and stand in one of `rooms` (any, with none).
func _interactables(root: Node, rooms: Array) -> int:
	var count := 0
	for node in root.find_children("*", "", true, false):
		if not node.has_method("get_interactions"):
			continue
		if (node.get_interactions() as Array).is_empty():
			continue
		var at: Vector2 = node.global_position
		if rooms.is_empty() or rooms.any(
				func(r: Dictionary) -> bool: return (r["rect"] as Rect2).has_point(at),
		):
			count += 1
	return count
