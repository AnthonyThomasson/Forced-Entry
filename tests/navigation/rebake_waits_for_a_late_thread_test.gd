extends GameTest
## A planning re-bake whose thread is later than its frame holds that frame: the district's bake
## takes tens of ms, the frame count here is one, so the thread is still running when the frame
## comes and the result is waited for. It lands on the frame anyway, whole (the polygon has its
## mesh), and is counted (`NavBake.late`).


func describe() -> Dictionary:
	return {
		"name": "A re-bake waits for a late thread",
		"description": "With the landing frame one physics frame on, a district's bake is still "
			+ "running; the result is awaited and lands on that frame, whole, counted as late.",
		"tags": ["navigation", "bake", "rebake", "district"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)
	s.switch(&"nav.rebake", false)
	s.set_static(NavBakeConfig, &"district_frames", 1)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district: Node2D = t.world.district
	var rooms := WorldGen.district_rooms(district)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var before := region.navigation_polygon
	var late_before := NavBake.late
	var started := Engine.get_physics_frames()
	var landed_at := [-1]  # a lambda captures an int by value
	NavBuilder.rebake_async(
		region, district, rooms, NavBuilder.AGENT_RADIUS,
		func() -> void: landed_at[0] = Engine.get_physics_frames(),
	)
	if not t.require(await t.until(func(): return landed_at[0] >= 0, 5.0), "the bake lands"):
		return
	t.check(landed_at[0] - started == 1, "it lands on its frame (%d on)" % (landed_at[0] - started))
	t.check(NavBake.late == late_before + 1, "the thread was late and was waited for")
	var landed := region.navigation_polygon
	t.check(landed != before, "the region holds the new polygon")
	t.check(landed.get_polygon_count() > 100, "whole: %d polygons" % landed.get_polygon_count())
