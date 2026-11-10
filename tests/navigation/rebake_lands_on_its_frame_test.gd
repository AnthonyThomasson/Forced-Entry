extends GameTest
## A planning re-bake's result is taken in on a fixed physics frame, `NavBakeConfig.house_frames`
## after it started, not whenever its worker thread finishes: until that frame the region holds the
## previous polygon, on it the new one is assigned and `done` called, every time. The same count
## whatever the thread's wall-clock is what makes a match play the same fight on every run.


func describe() -> Dictionary:
	return {
		"name": "A re-bake lands on its fixed frame",
		"description": "rebake_async leaves the region's polygon alone until the physics frame "
			+ "house_frames after it started, then assigns it and calls back, three times over.",
		"tags": ["navigation", "bake", "rebake"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children(
		"*", "NavigationRegion2D", true, false,
	)[0]
	for attempt in 3:
		var before := region.navigation_polygon
		var started := Engine.get_physics_frames()
		var landed_at := [-1]  # a lambda captures an int by value
		NavBuilder.rebake_async(
			region, t.world.house, t.rooms, NavBuilder.AGENT_RADIUS,
			func() -> void: landed_at[0] = Engine.get_physics_frames(),
		)
		var early := false
		for i in NavBakeConfig.house_frames * 2:
			if landed_at[0] >= 0:
				break
			early = early or region.navigation_polygon != before
			await t.frames(1)
		t.check(
			not early,
			"attempt %d: the region keeps its polygon until the bake lands" % attempt,
		)
		if not t.require(landed_at[0] >= 0, "attempt %d: the bake lands and calls back" % attempt):
			return
		t.check(
			landed_at[0] - started == NavBakeConfig.house_frames,
			"attempt %d: it lands %d physics frames after it started (%d)"
				% [attempt, NavBakeConfig.house_frames, landed_at[0] - started],
		)
		t.check(
			region.navigation_polygon != before,
			"attempt %d: the region holds the new polygon once it has landed" % attempt,
		)
