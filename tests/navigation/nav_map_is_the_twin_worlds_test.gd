extends GameTest
## The nav's map is the navigation map of the twin space's `World3D` (#194 nav3d-b, interface 9 /
## 29): `TwinWorlds.world_in` finds that world from the sim's `World2D`, `NavWorld.map_of` (a node)
## and `NavWorld.map_in` (the `World2D`) answer its map.


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
