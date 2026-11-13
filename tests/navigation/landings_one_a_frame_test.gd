extends GameTest
## Planning, ring and avoid bakes never land more than one on a `GameClock` frame (#195). Every
## landing welds a polygon, assigns it and so makes its map synchronise on the next step, and a
## frame that held six of them (a planning bake, the ring and four avoid maps started in the same
## few frames) cost 37 to 40 ms in the 5v5 guard, with the bakes whose thread was late waiting for
## it in the same frame. A landing that comes due on a frame that already holds one slips to the
## next frame, in the order the bakes were started, so the same frames on every run.
## Here five avoid maps and a re-bake are started in one frame: all are due on the same frame
## (`NavBakeConfig.house_frames` on), and they land one a frame in the order they were asked, the
## first on its due frame, the last `ASKED - 1` frames after it.

const ARENA := Rect2(0, 0, 800, 500)
## Avoid maps asked in the one frame; the re-bake is one more landing.
const ASKED := 5


func describe() -> Dictionary:
	return {
		"name": "Bakes land one a frame, in the order they were started",
		"description": "Five avoid maps and a re-bake started in one frame come due on one frame: "
			+ "no frame takes in two, they land in the order asked, the first on its due frame "
			+ "and the last within the number of bakes of it.",
		"tags": ["navigation", "bake", "rebake", "avoid"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region := NavBuilder.planning_region(t.world.get_world_2d().navigation_map)
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var landed: Array[int] = []  # the GameClock frame of each landing, in the order asked
	landed.resize(ASKED + 1)
	landed.fill(-1)
	var regions: Array[NavigationRegion2D] = []
	var start := GameClock.frame()
	for i in ASKED:
		var hole := PackedVector2Array([
			Vector2(100 + i * 100, 100), Vector2(140 + i * 100, 100),
			Vector2(140 + i * 100, 400), Vector2(100 + i * 100, 400),
		])
		NavBuilder.avoid_map(region, "key%d" % i, [hole])
		regions.append(region.get_child(region.get_child_count() - 1) as NavigationRegion2D)
	NavBuilder.rebake_async(
		region, t.world.house, t.rooms, NavBuilder.AGENT_RADIUS,
		func() -> void: landed[ASKED] = GameClock.frame(),
	)
	for _frame in NavBakeConfig.house_frames + 3 * ASKED:
		await t.frames(1)
		for i in ASKED:
			if landed[i] < 0 and regions[i].navigation_polygon != null:
				landed[i] = GameClock.frame()
	if not t.require(not landed.has(-1), "every bake landed (frames %s)" % str(landed)):
		return
	var frames := landed.duplicate()
	frames.sort()
	for i in range(1, frames.size()):
		t.check(
			frames[i] > frames[i - 1],
			"no frame took in two bakes (landed on %s)" % str(landed),
		)
		if frames[i] == frames[i - 1]:
			break
	t.check(
		frames[0] - start <= NavBakeConfig.house_frames + 1,
		"the first landing is on its due frame (%d frames after the ask, due at %d)"
			% [frames[0] - start, NavBakeConfig.house_frames],
	)
	t.check(
		frames[-1] - frames[0] <= ASKED,
		"all %d landed within %d frames of the first (%s)" % [ASKED + 1, ASKED, str(landed)],
	)
	var in_order := true
	for i in range(1, ASKED):
		in_order = in_order and landed[i] > landed[i - 1]
	t.check(in_order, "the avoid maps landed in the order they were asked (%s)" % str(landed))
