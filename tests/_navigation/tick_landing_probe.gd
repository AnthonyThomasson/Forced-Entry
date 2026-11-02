extends RefCounted
## Shared by the tests that a re-bake lands in the frame of the updater's tick (not a test itself):
## `const TickLanding := preload("res://tests/_navigation/tick_landing_probe.gd")`. `watch` counts
## the ticks of the updater's timer from now on and notes the first at which any of the steering
## regions carries a polygon other than the one it has now (a re-bake replaces it). The callback is
## connected after the updater's own, so it runs in the frame of the tick, after the part of the
## tick the updater did without waiting a frame.

## Ticks of the timer since `watch`, and the first at which a steering polygon had changed (-1:
## none).
var fired := 0
var landed_at := -1
var _regions: Array[NavigationRegion2D] = []
var _before: Array = []


## Start counting `world`'s nav updater ticks against the polygons `regions` have now.
func watch(world: Node, regions: Array[NavigationRegion2D]) -> void:
	_regions = regions
	_before = regions.map(
		func(region: NavigationRegion2D) -> NavigationPolygon: return region.navigation_polygon,
	)
	var timer := world.get_node("NavUpdater/RebakeTimer") as Timer
	timer.timeout.connect(_on_tick)


## One tick of the timer.
func _on_tick() -> void:
	fired += 1
	if landed_at >= 0:
		return
	for i in _regions.size():
		if _regions[i].navigation_polygon != _before[i]:
			landed_at = fired
			return
