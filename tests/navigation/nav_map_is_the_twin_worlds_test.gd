extends GameTest
## The nav's map is the navigation map of the twin space's `World3D` (#194 nav3d-b, interface 9 /
## 29): `TwinWorlds.world_in` finds that world from the sim's `World2D`, `NavWorld.map_of` (a node)
## and `NavWorld.map_in` (the `World2D`) answer its map. A map the nav builds on takes the bake's
## cell size and height whatever it was made with (the server refuses a mesh of another cell).

const MainProbe := preload("res://tests/_main/main_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The nav map is the twin world's",
		"description": "TwinWorlds.world_in finds the twin space's World3D, and NavWorld answers "
			+ "its navigation map for a node and for the World2D.",
		"tags": ["navigation", "twin"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.object(&"shelf", "bookshelf", Vector2(200, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.3)
	var shelf: Node = t.object(&"shelf")
	var world := shelf.get_viewport().find_world_2d()
	var twins := TwinWorlds.world_in(world)
	if not t.require(twins != null, "the sim's World2D has a twin world beside it"):
		return
	t.check(NavWorld.map_of(shelf) == twins.navigation_map, "a node's map is the twin world's")
	t.check(NavWorld.map_in(world) == twins.navigation_map, "the World2D's map is the twin world's")
	t.check(NavBuilder.ready(NavWorld.map_of(shelf)), "the map has taken the house's region in")
	t.expect_eq(
		NavigationServer3D.map_get_cell_size(twins.navigation_map), NavSource.CELL_SIZE,
		"the twin map's cell size is the bake's",
	)
	t.expect_eq(
		NavigationServer3D.map_get_cell_height(twins.navigation_map), NavSource.CELL_HEIGHT,
		"the twin map's cell height is the bake's",
	)
	await _bare_map_takes_the_bakes_cell(t)


## A world with no twin space, whose 3D world's map was made with another cell, is put on the
## bake's by the build that adds a region to it; and `map_in` answers that map until the world goes.
func _bare_map_takes_the_bakes_cell(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var odd := 1.0
	var map := viewport.find_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, odd)
	NavigationServer3D.map_set_cell_height(map, odd)
	var world := Node2D.new()
	viewport.add_child(world)
	var house := WorldGen.generate(5, "", Vector2.ZERO, world)
	NavBuilder.build(house, WorldGen.get_rooms(house), world)
	t.check(NavWorld.map_of(world) == map, "a world with no twins is on its viewport's 3D map")
	await t.seconds(0.3)  # the server takes a map's settings in at its next flush
	t.expect_eq(
		NavigationServer3D.map_get_cell_size(map), NavSource.CELL_SIZE,
		"a map made with another cell size is put on the bake's by the build",
	)
	t.expect_eq(
		NavigationServer3D.map_get_cell_height(map), NavSource.CELL_HEIGHT,
		"and its cell height",
	)
	t.check(
		NavWorld.map_in(viewport.find_world_2d()) == map,
		"map_in answers the map map_of found for the world",
	)
