extends GameTest
## Interface 9, #194 nav3d-b: a route and a snap asked of the 3D server (`NavigationServer3D`, a
## plan point (x, z) as the vector (x, 0, z)) are the 2D server's answers, to the point, on a
## house's map: the 2D server of the engine (4.4) is a wrapper over the 3D one on the same map RID,
## and the nav moves to the 3D server for good on that ground. Every closest point of a grid of
## probes and the route of a stride of ordered pairs of them are asked both ways (`NavQueryProbe`).


func describe() -> Dictionary:
	return {
		"name": "The 3D server's routes and snaps are the 2D server's on a house",
		"description": "A grid of probe points and a stride of ordered pairs over a house's map: "
			+ "closest point and path from NavigationServer3D equal NavigationServer2D's.",
		"tags": ["navigation"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1)


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	NavQueryProbe.compare(t, "house", t.world.get_world_2d().navigation_map)
