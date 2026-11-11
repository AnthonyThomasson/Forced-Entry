extends GameTest
## A re-bake's landing frame is counted on `GameClock.frame()`, the frame the AI's timers and
## `WorldRng.frame_of` count, not on the engine's physics frames, which run through a pause: a bake
## started, the tree paused for a while, lands the same number of AI frames later as an unpaused one
## (`NavBakeConfig.house_frames`), and that many engine frames plus the paused stretch later.

const PAUSED_FRAMES := 7


func describe() -> Dictionary:
	return {
		"name": "A re-bake's landing counts game-clock frames",
		"description": "A bake started, the tree paused for a few frames, lands house_frames "
			+ "GameClock frames after its start and the paused engine frames later in engine "
			+ "frames, so a paused match lands bakes on the same AI frame as an unpaused one.",
		"tags": ["navigation", "bake", "rebake", "pause"],
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
	var started_engine := Engine.get_physics_frames()
	var started_clock := GameClock.frame()
	var landed := [-1, -1]  # engine frame, clock frame (a lambda captures an int by value)
	NavBuilder.rebake_async(
		region, t.world.house, t.rooms, NavBuilder.AGENT_RADIUS,
		func() -> void:
			landed[0] = Engine.get_physics_frames()
			landed[1] = GameClock.frame(),
	)
	await t.frames(2)
	t.world.get_tree().paused = true
	await t.frames(PAUSED_FRAMES)
	t.world.get_tree().paused = false
	for i in NavBakeConfig.house_frames * 2:
		if landed[0] >= 0:
			break
		await t.frames(1)
	t.world.get_tree().paused = false
	if not t.require(landed[0] >= 0, "the bake lands and calls back"):
		return
	t.check(
		landed[1] - started_clock == NavBakeConfig.house_frames,
		"it lands %d game-clock frames after it started, a pause between (%d)"
			% [NavBakeConfig.house_frames, landed[1] - started_clock],
	)
	t.check(
		landed[0] - started_engine > NavBakeConfig.house_frames + PAUSED_FRAMES - 3,
		"the engine's frames ran through the pause (%d)" % (landed[0] - started_engine),
	)
