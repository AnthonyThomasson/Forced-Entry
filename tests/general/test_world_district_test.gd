extends GameTest
## A test world can be a downtown district (#182): `s.district(seed, plan, entrance)` builds it
## through `WorldGen.generate_district`, and the world's `rooms` and `openings` (what every injected
## NPC and test read, `t.rooms` and `t.world.openings`) are the HOUSE'S, the centre tower's, not all
## nine towers'. The house's front door lands on `entrance`, the plan is the centre tower's, and the
## district root is `t.world.district` (its towers read through `DistrictReads`).

const ENTRANCE := Vector2(3000, 2000)
const SEED := 7
const PLAN := "garage_home"
const TOWERS := 9
## How close (px) the front door must be to the entrance.
const SLACK := 0.5


func describe() -> Dictionary:
	return {
		"name": "A test world can be a district whose rooms and doorways are the house's",
		"description": "s.district builds nine towers and their streets; t.rooms and t.openings "
			+ "are the centre house's, its front door on the entrance.",
		"tags": ["setup", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN, ENTRANCE)


func run(t: TestContext) -> void:
	var district := t.world.get("district") as Node2D
	if not t.require(district != null, "the world holds the district"):
		return
	var towers := DistrictReads.get_towers(district)
	t.check(towers.size() == TOWERS, "%d towers" % towers.size())
	t.check(towers[DistrictLayout.HOUSE_BLOCK]["plan"] == PLAN, "the centre tower is the plan")
	var house := WorldGen.house_of(district)
	t.check(house != null and house == t.world.house, "the world's house is the centre tower")
	t.check(t.rooms == WorldGen.get_rooms(house), "t.rooms are the house's")
	t.check(t.rooms.size() < WorldGen.district_rooms(district).size(), "not every tower's")
	t.check(
		t.world.openings == WorldGen.get_openings(house),
		"the world's openings are the house's",
	)
	var openings: Array = t.world.openings
	var fronts := openings.filter(func(o: Dictionary) -> bool: return o["front"])
	t.require(fronts.size() == 1, "one front doorway")
	t.check(((fronts[0]["pos"] as Vector2) - ENTRANCE).length() <= SLACK, "the front door is on it")
	t.check(district.get_parent() == t.world, "the district hangs off the world root")
