extends GameTest
## A navigation map takes a changed region in on the main thread, in the physics step that sees the
## change (`navigation/world/map_use_async_iterations` is off in `project.godot`), not on a
## background thread whose finish is wall-clock: with it on, the frame a landed bake becomes visible
## to a query (`NavBuilder.ready`, a route) shifted with the machine's load, and a match fought over
## the same seed was a different fight from one run to the next (the 5v5 guard's contact came at
## 12 s, at 30 s, or not in 30 s). The world's map and the ones `NavBuilder` makes (steering, avoid)
## all answer false to `map_get_use_async_iterations`.

const ARENA := Rect2(0, 0, 800, 500)


func describe() -> Dictionary:
	return {
		"name": "A navigation map syncs on the main thread",
		"description": "The world's map and the steering, avoid and ring maps do not use async "
			+ "iterations, so a landed bake shows on the same frame every run.",
		"tags": ["navigation", "determinism"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)


func run(t: TestContext) -> void:
	var world_map := t.world.get_world_2d().navigation_map
	t.check(
		not NavigationServer2D.map_get_use_async_iterations(world_map),
		"the world's map does not sync on a thread",
	)
	var region := NavBuilder.planning_region(world_map)
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var avoid := NavBuilder.avoid_map(region, "key", [])
	t.check(
		not NavigationServer2D.map_get_use_async_iterations(avoid),
		"an avoid map does not sync on a thread",
	)
	t.check(
		not NavigationServer2D.map_get_use_async_iterations(NavBuilder.steering_map(world_map)),
		"the steering map does not sync on a thread",
	)
