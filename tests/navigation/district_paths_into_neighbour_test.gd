extends GameTest
## The nav map of a district (#182) covers every tower and every street out to the shells, and the
## shells stay off it: a path from the street outside the house's front door reaches a room in each
## of the eight neighbour towers (through that tower's own doorway), the outer street, out at the
## corners of the grid, is on the map, and a point in a shell is not (nothing paths into it).
##
## The doorways' frames are the test's own, read off each tower's rooms and openings
## (`tests/_ai/slots_probe.gd`); the map is read through the engine's own path and closest-point
## queries on the world's navigation map.

const Slots := preload("res://tests/_ai/slots_probe.gd")
const SEED := 7
## How far (px) out of the house's front door the path starts, and how far into a neighbour's front
## room (from its door) it aims.
const START_OUT := 70.0
const INTO_ROOM := 45.0
## How near (px) a point on the map is to it, and how near the end of a path is to the point it was
## asked to reach.
const ON_MAP := 3.0
const REACHED := 30.0
## A point in a shell is at least this far (px) from the map (a shell is 320 px deep, its centre
## far from the street and its walls).
const SHELL_FAR := 100.0
## How far (px) in from the grid's streets' corner the outer street's test point stands: the middle
## of the 200 px asphalt.
const CORNER_IN := 100.0


func describe() -> Dictionary:
	return {
		"name": "A district's nav map paths into neighbour towers and leaves the shells off it",
		"description": "From outside the house's front door a path reaches a room in each of the "
			+ "eight neighbour towers; the outer street's corners are on the map; a point in a "
			+ "shell is off it.",
		"tags": ["navigation", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)


func run(t: TestContext) -> void:
	var district := t.world.get("district") as Node2D
	if not t.require(district != null, "the world holds the district"):
		return
	var map := t.world.get_world_2d().navigation_map
	var towers := DistrictReads.get_towers(district)
	var start := _start(towers[DistrictLayout.HOUSE_BLOCK])
	for tower: Dictionary in towers:
		if tower["block"] != DistrictLayout.HOUSE_BLOCK:
			_check_reaches(t, map, start, tower)
	_check_outer_street(t, map, district)
	_check_shells(t, map, district)


## The point `START_OUT` px out of `tower`'s front door, along the way out of its room.
func _start(tower: Dictionary) -> Vector2:
	var frame := _front_frame(tower)
	return (frame["pos"] as Vector2) + (frame["out"] as Vector2) * START_OUT


## The frame of `tower`'s front door (`Slots.frame`, into the room it opens to).
func _front_frame(tower: Dictionary) -> Dictionary:
	var front: Dictionary = tower["front"]
	return Slots.frame(front, String(front["rooms"][0]), WorldGen.get_rooms(tower["node"]))


## A path from `start` ends in the front room of `tower`, a neighbour: it ends near the point just
## inside its front door, and that point is itself on the map.
func _check_reaches(t: TestContext, map: RID, start: Vector2, tower: Dictionary) -> void:
	var frame := _front_frame(tower)
	var target: Vector2 = (frame["pos"] as Vector2) - (frame["out"] as Vector2) * INTO_ROOM
	var label := "tower %d" % tower["block"]
	t.check(
		NavigationServer2D.map_get_closest_point(map, target).distance_to(target) <= REACHED,
		"%s: the room just inside its front door %s is on the map" % [label, str(target.round())],
	)
	var path := NavigationServer2D.map_get_path(map, start, target, true)
	if not t.check(not path.is_empty(), "%s: a path leads there from the house's front" % label):
		return
	var end := path[path.size() - 1]
	t.check(
		end.distance_to(target) <= REACHED and (frame["room"] as Rect2).has_point(end),
		"%s: the path ends in its front room (at %s, aiming for %s)"
			% [label, str(end.round()), str(target.round())],
	)


## The outer street's corners, out of the grid's towers, are on the map.
func _check_outer_street(t: TestContext, map: RID, district: Node2D) -> void:
	var streets := WorldGen.district_bounds(district)
	for corner: Vector2 in [
		streets.position + Vector2(CORNER_IN, CORNER_IN),
		streets.end - Vector2(CORNER_IN, CORNER_IN),
		Vector2(streets.end.x - CORNER_IN, streets.position.y + CORNER_IN),
		Vector2(streets.position.x + CORNER_IN, streets.end.y - CORNER_IN),
	]:
		t.check(
			NavigationServer2D.map_get_closest_point(map, corner).distance_to(corner) <= ON_MAP,
			"the outer street at %s is on the map" % str(corner.round()),
		)


## A point in the middle of every shell is off the map.
func _check_shells(t: TestContext, map: RID, district: Node2D) -> void:
	var shells := DistrictReads.get_shells(district)
	if not t.require(not shells.is_empty(), "premise: the district has shells"):
		return
	for shell: Dictionary in shells:
		var centre: Vector2 = (shell["rect"] as Rect2).get_center()
		t.check(
			NavigationServer2D.map_get_closest_point(map, centre).distance_to(centre) >= SHELL_FAR,
			"the shell at %s is off the map" % str(centre.round()),
		)
