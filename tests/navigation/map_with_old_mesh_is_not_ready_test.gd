extends GameTest
## Interface 9: a map that still answers from a previous navmesh is not ready (`NavBuilder.ready`).
## A world with no twin space shares its viewport's 3D map (`NavWorld.map_of`): a second house built
## into it joins a map that is live with the first's mesh and takes it in a frame or so later, and a
## query in between is answered by the first house's mesh. `ready` stays false until a query at the
## second house answers from its own region.

const MainProbe := preload("res://tests/_main/main_probe.gd")
## Far from the first house: the first mesh's closest point to the second is plainly not on it.
const FAR := Vector2(3000, 0)


func describe() -> Dictionary:
	return {
		"name": "A map showing the previous navmesh is not ready",
		"description": "Two houses built in turn into one bare world's map: ready after the first, "
			+ "not ready right after the second joins, ready once the second is taken in.",
		"tags": ["navigation", "bake"],
		"timeout": 10.0,
	}


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var world := Node2D.new()
	viewport.add_child(world)
	var first := WorldGen.generate(5, "", Vector2.ZERO, world)
	NavBuilder.build(first, WorldGen.get_rooms(first), world)
	var map := NavWorld.map_of(world)
	t.require(
		await t.until(func(): return NavBuilder.ready(map), 3.0), "the first house's map is ready",
	)
	var second := WorldGen.generate(6, "", FAR, world)
	var rooms := WorldGen.get_rooms(second)
	NavBuilder.build(second, rooms, world)
	t.check(NavWorld.map_of(world) == map, "the second house joins the same map")
	t.check(
		NavPlan.iteration(map) != 0,
		"premise: the map is live, with the first house's mesh, when the second joins",
	)
	t.check(not NavBuilder.ready(map), "the map is not ready while it shows the previous mesh")
	var centre: Vector2 = (rooms[0]["rect"] as Rect2).get_center()
	t.check(
		NavBuilder.snap(map, centre) == centre,
		"and a snap on it answers the point asked, not the first mesh's corner",
	)
	t.check(
		await t.until(func(): return NavBuilder.ready(map), 3.0),
		"the map is ready once it has taken the second house in",
	)
	t.check(
		NavBuilder.snap(map, centre).distance_to(centre) < 200.0,
		"and a snap at the second house lands on it",
	)
