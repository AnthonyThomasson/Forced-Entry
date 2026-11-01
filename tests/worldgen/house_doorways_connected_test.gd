extends GameTest
## Every generated house is walkable and logical: within each room all of its doorways reach one
## another on the baked nav map, each doorway can be passed through, and every room is reachable
## from outside the front entrance; and LayoutRules.check finds nothing illogical in it (front door
## in a living space on the south wall, legal exits and doors, bathrooms are dead ends, no
## pass-through rooms) and it has at most one exit. The layout (rooms, doorways, exits) depends only
## on the plan and the seed's mirror draw, never on the furnishing, so these checks share the houses
## this test builds anyway.

const Reach := preload("res://tests/_worldgen/doorway_reach_probe.gd")
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]


func describe() -> Dictionary:
	return {
		"name": "Every doorway in a generated house is reachable",
		"description": "For every floorplan and several seeds: LayoutRules finds the layout "
			+ "logical, all doorways of a room are mutually reachable, each doorway can be walked "
			+ "through, and every room is reachable from the front entrance.",
		"tags": ["worldgen", "navigation", "house", "doorway", "layout"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	for plan in HouseDefinitions.get_all():
		for house_seed in SEEDS:
			await Reach.check_house(t, plan, house_seed)
