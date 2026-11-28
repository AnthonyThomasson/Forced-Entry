extends GameTest
## A district's planning bake with doors standing open, their leaves carved (#183), makes a mesh
## and logs nothing: the baker's polygon beside a leaf's strip can hold a spur of no width (an edge
## and its reverse), and `NavMerge` once merged that ring with itself, lost it and read an empty
## ring (a modulo by zero logged by `_union`). Every polygon the bake makes is a real one.

const SEED := 7


func describe() -> Dictionary:
	return {
		"name": "A district bakes with its doors standing open",
		"description": "Every door of a district is opened to its stop, their leaves carved: a "
			+ "planning bake makes a mesh of whole polygons and logs no error.",
		"tags": ["navigation", "district", "door", "bake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.district as Node2D
	var region := t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	for door in NavLeaves.doors_of(district):
		door.call("open_fully", null)
	await t.seconds(2.0)
	var carved := 0
	for door in NavLeaves.doors_of(district):
		if not NavLeaves.hole(door).is_empty():
			carved += 1
	if not t.require(carved > 0, "premise: open leaves are carved (%d)" % carved):
		return
	var site := NavBuilder.site_of(region, district, WorldGen.district_rooms(district))
	var baked := NavSource.bake(
		NavSource.job(site, NavBuilder.furniture_holes(district)), district.position)
	t.check(baked.get_polygon_count() > 0, "the bake made a mesh")
	for i in baked.get_polygon_count():
		if baked.get_polygon(i).size() < 3:
			t.check(false, "polygon %d has %d corners" % [i, baked.get_polygon(i).size()])
			return
	t.check(true, "every polygon has three corners or more")
