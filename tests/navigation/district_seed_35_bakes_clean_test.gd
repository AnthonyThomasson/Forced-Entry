extends GameTest
## District seed 35 bakes without an engine error. On the 2D baker's mesh its bake logged
## "Navigation map synchronization error. Attempted to merge a navigation mesh polygon edge with
## another already-merged edge" (the runner fails a test on any logged engine error; the same error
## once showed as a flake of an unrelated test that ran a bake in its process). Red on the 2D baker
## (4671b7a9), green on the grid baker.

const Bake := preload("res://tests/_navigation/bake_probe.gd")
const SEED := 35


func describe() -> Dictionary:
	return {
		"name": "District seed 35 bakes without an engine error",
		"description": "A district of seed 35 is built and its planning and steering maps are "
			+ "given time to land and a character's stop re-bakes tiles: the NavigationServer logs "
			+ "no error and the planning region's polygon has no edge it could not merge.",
		"tags": ["navigation", "district", "weld"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(2.0)
	var region := t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	var why := Bake.problem(region as NavigationRegion3D)
	t.check(why == "", "the planning polygon has nothing the server rejects: %s" % why)
	for tile: NavigationRegion3D in NavBuilder.steering_regions(region as NavigationRegion3D):
		var tile_why := Bake.problem(tile)
		if tile_why != "":
			t.check(false, "a steering tile has nothing the server rejects: %s" % tile_why)
			break
