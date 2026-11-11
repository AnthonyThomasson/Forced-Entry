extends GameTest
## An avoid map's bake (`NavBuilder.avoid_map`) is taken in on a fixed physics frame, like a
## planning re-bake's (`rebake_lands_on_its_frame`): its region holds no polygon until the physics
## frame `NavBakeConfig.house_frames` after the first ask, then holds the bake, whichever frame its
## worker thread finished on.

const ARENA := Rect2(0, 0, 800, 500)
const HOLE := [Vector2(380, 100), Vector2(420, 100), Vector2(420, 400), Vector2(380, 400)]


func describe() -> Dictionary:
	return {
		"name": "An avoid map lands on its fixed frame",
		"description": "avoid_map's region keeps no polygon until the physics frame house_frames "
			+ "after the first ask, then holds the bake, for two keys in turn.",
		"tags": ["navigation", "bake", "avoid"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var region := NavBuilder.planning_region(t.world.get_world_2d().navigation_map)
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	for key in ["first", "second"]:
		var started := Engine.get_physics_frames()
		var map := NavBuilder.avoid_map(region, key, [PackedVector2Array(HOLE)])
		var avoid_region := _newest(region)
		var landed_after := -1
		for i in NavBakeConfig.house_frames * 2:
			if avoid_region.navigation_polygon != null:
				landed_after = Engine.get_physics_frames() - started
				break
			await t.frames(1)
		if not t.require(landed_after >= 0, "%s: the avoid map's bake lands" % key):
			return
		t.check(
			landed_after == NavBakeConfig.house_frames,
			"%s: it lands %d physics frames after the ask (%d)"
				% [key, NavBakeConfig.house_frames, landed_after],
		)
		t.check(
			await t.until(func(): return NavBuilder.ready(map), 5.0),
			"%s: the map answers queries once it has landed" % key,
		)


## The avoid region added last under `region` (a second one is named by the engine).
func _newest(region: NavigationRegion2D) -> NavigationRegion2D:
	return region.get_child(region.get_child_count() - 1) as NavigationRegion2D
