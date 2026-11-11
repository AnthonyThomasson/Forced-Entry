extends GameTest
## A re-bake lands exactly `NavBakeConfig.house_frames` steps after it started, wherever in the step
## it was started (a node's `_physics_process`, which runs after `GameClock` has ticked, or a
## coroutine woken by `physics_frame`, which runs before), and its count is `GameClock`'s frames,
## the ones the AI's timers and `WorldRng.frame_of` count, not the engine's physics frames, which
## run through a pause: a bake with the tree paused for a while lands the same number of game
## frames after its start, that many engine frames plus the paused stretch.

const PAUSED_FRAMES := 7


func describe() -> Dictionary:
	return {
		"name": "A re-bake's landing counts game-clock frames from anywhere in the step",
		"description": "A bake started from a _physics_process or a coroutine lands house_frames "
			+ "frames later; with the tree paused for a few frames between, house_frames GameClock "
			+ "frames later and the paused engine frames after that.",
		"tags": ["navigation", "bake", "rebake", "pause"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake lands a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children(
		"*", "NavigationRegion2D", true, false,
	)[0]
	var count := NavBakeConfig.house_frames
	# From a node's _physics_process.
	var starter := Starter.new()
	t.world.add_child(starter)
	var from_process := _Run.new()
	starter.start = func() -> void: from_process.begin(t, region)
	await _until_landed(t, from_process)
	starter.queue_free()
	_check_lands(t, from_process, "started in _physics_process")

	# From a coroutine.
	var from_coroutine := _Run.new()
	from_coroutine.begin(t, region)
	await _until_landed(t, from_coroutine)
	_check_lands(t, from_coroutine, "started from a coroutine")

	# With a pause between.
	var paused := _Run.new()
	paused.begin(t, region)
	await t.frames(2)
	t.world.get_tree().paused = true
	await t.frames(PAUSED_FRAMES)
	t.world.get_tree().paused = false
	await _until_landed(t, paused)
	if t.require(paused.landed[0] >= 0, "a bake paused over lands"):
		t.check(
			paused.clock_frames() == count,
			"with a pause between, it lands %d game-clock frames on (%d)"
				% [count, paused.clock_frames()],
		)
		t.check(
			paused.engine_frames() == count + PAUSED_FRAMES,
			"the engine's frames ran through the %d paused (%d)"
				% [PAUSED_FRAMES, paused.engine_frames()],
		)


## Check `bake` landed, exactly `NavBakeConfig.house_frames` frames after its start.
func _check_lands(t: TestContext, bake: _Run, what: String) -> void:
	if t.require(bake.landed[0] >= 0, what + ": the bake lands"):
		t.check(
			bake.engine_frames() == NavBakeConfig.house_frames,
			"%s, it lands %d frames on (%d)"
				% [what, NavBakeConfig.house_frames, bake.engine_frames()],
		)


## Wait (at most twice a bake's count, and the paused stretch) for `bake` to land.
func _until_landed(t: TestContext, bake: _Run) -> void:
	for i in NavBakeConfig.house_frames * 2 + PAUSED_FRAMES:
		if bake.landed[0] >= 0:
			return
		await t.frames(1)


## A node that starts a bake from its own `_physics_process`, once.
class Starter extends Node:
	var start := Callable()

	func _physics_process(_delta: float) -> void:
		if start.is_valid():
			var go := start
			start = Callable()
			go.call()


## One bake: the engine and clock frames it started and landed on (arrays: a lambda captures an
## int by value).
class _Run extends RefCounted:
	var started := [-1, -1]
	var landed := [-1, -1]

	func begin(t: TestContext, region: NavigationRegion2D) -> void:
		started = [Engine.get_physics_frames(), GameClock.frame()]
		var here := self
		NavBuilder.rebake_async(
			region, t.world.house, t.rooms, NavBuilder.AGENT_RADIUS,
			func() -> void:
				here.landed = [Engine.get_physics_frames(), GameClock.frame()],
		)

	func engine_frames() -> int:
		return landed[0] - started[0]

	func clock_frames() -> int:
		return landed[1] - started[1]
