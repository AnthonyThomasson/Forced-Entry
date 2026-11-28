extends GameTest
## A turned chair beside a wall cuts the planning navmesh with its hole, and the cut can leave
## vertices a fraction of a pixel apart: the NavigationServer merges edges by 1 px cell, rejects an
## edge whose ends share one and logs "navigation map synchronization error" (any logged engine
## error fails a test). The grid baker's vertices stand on whole cells, so these spots bake clean
## (the 2D baker's mesh needed a weld, `NavWeld`, now gone: it changed none of 1042 bakes of a full
## run). They are chair spots where an unwelded 2D planning bake went wrong
## (found by a random search of 600 placements), baked both ways (in place and on the server's
## worker thread).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Bake := preload("res://tests/_navigation/bake_probe.gd")
const SPOTS := [
	[Vector2(885.1079, 149.3317), 3.55461406707764],
	[Vector2(811.0822, 205.5673), 5.71764612197876],
]


func describe() -> Dictionary:
	return {
		"name": "Furniture beside a wall bakes a clean navmesh",
		"description": "A chair turned at spots beside the terrace house's walls and the planning "
			+ "region is re-baked each time, in place and off the main thread: no polygon edge "
			+ "collapses into one cell, no edge is shared by three polygons, and the map syncs "
			+ "without an engine error.",
		"tags": ["navigation", "rebake", "furniture", "weld"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(740, 60), { "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var map: RID = NavWorld.map_of(t.world)
	var chair: Node2D = t.object(&"chair")
	var problems := []
	for spot: Array in SPOTS:
		chair.global_position = spot[0]
		chair.rotation = spot[1]
		for off_thread in [false, true]:
			if off_thread:
				var done := [false]
				NavBuilder.rebake_async(
					region,
					t.world.house,
					t.rooms,
					14.0,
					func(): done[0] = true,
				)
				await t.until(func(): return done[0], 5.0, "the off-thread bake lands")
			else:
				NavBuilder.rebake(region, t.world.house, t.rooms)
			var why := Bake.problem(region)
			if why != "":
				problems.append("%s turned %.2f (%s): %s" % [
					spot[0],
					spot[1],
					"off the main thread" if off_thread else "in place",
					why,
				])
			NavigationServer3D.map_force_update(map)
			await t.frames(2)
	t.check(
		problems.is_empty(),
		"every baked navmesh has edges the server can merge: %s" % str(problems),
	)
