class_name NavBake extends RefCounted
## Navigation domain: one re-bake's thread and its landing. The bake runs on a thread of the
## `WorkerThreadPool`, and its result is taken in (assigned to its region, `landed` called) on the
## game frame its count says after the thread's start (`NavBakeConfig`), not when the thread happens
## to finish: the same frame every run. The thread starts at the ask, but no more than
## `NavBakeConfig.at_once` bakes, the urgent ring's apart, are between start and landing (their
## places): one asked past that waits, starts when a landing frees a place, the oldest first
## (`NavTurns`), and counts from that start, so it lands later rather than holding a frame for a
## thread queued behind the others. A thread not done by its frame is waited for, which holds that
## frame (`was_late` says so of each bake, `late_total` counts them). A bake in flight is kept in
## `_flying` until it lands, so nothing frees it first. Never two land on one frame: each landing
## assigns a polygon and makes its map synchronise, and a late one holds the frame for the rest of
## its thread, so a bake due on a frame that already took one in lands on the next, in the order the
## bakes were started (`navigation/landings_one_a_frame`).
##
## A "frame" is counted on `GameClock.frame()`, the AI's own frame (`WorldRng.frame_of`, every
## timer), not `Engine.get_physics_frames()`: that one runs through a pause and the clock stands
## still, so a paused match lands its bakes on the same AI frame as an unpaused one. The count
## starts at the first `physics_frame` after the start and the bake lands on the `frames`-th one
## (`GameClock` has or has not ticked yet this step, depending on where the caller sits in the
## tree, and a count read at the start would follow that): a bake started anywhere in a physics step
## lands `frames` steps on, from a node's `_physics_process` or a coroutine alike.

## How many bakes were started (their thread, a waiting one's when its turn came), and how many of
## them were still running when their frame came, since the process began (a guard reads the rate: a
## creeping share of late bakes is a count that has fallen behind the thread).
static var started_total := 0
static var late_total := 0
## How many bakes have landed (their polygon taken in) since the process began.
static var landed_total := 0
## The bakes between their start and their landing.
static var _flying: Array[NavBake] = []
## The `GameClock` frame the last landing was taken in on, a bake's or a burst's: a landing due on
## that frame waits for the next (`_on_physics_frame`, `landing_taken`).
static var _landed_frame := -1
## Whether the root window's exit has been hooked to finish the bakes (`_finish_all`).
static var _exit_hooked := false

## Whether this bake's thread was still running when its frame came (known once it has landed).
var was_late := false
## The worker-pool task baking the polygon (-1 before its start and once it has landed), the
## `GameClock` frame it lands on (-1 until the first `physics_frame` after the start fixes it),
## the region (weakly), what to call once it has landed and the tree whose `physics_frame` signal
## drives it.
var _task := -1
var _due := -1
## How many frames the bake lands after its start (`start`'s `frames`).
var _frames := 0
## The navmesh of the job's `poly`, made by the worker once it has baked (`NavPlan.mesh_of`; one
## element, held in an array the worker fills and the landing reads after waiting for it), so the
## landing frame only assigns it.
var _mesh: Array[NavigationMesh] = []
var _region_ref: WeakRef
var _landed: Callable
var _tree: SceneTree
## What the thread is started from and what a waiting bake is asked (`start`'s `job`), with the
## region's offset as `origin`; its `poly` is the polygon baked and taken in.
var _job: Dictionary


## The game frames a bake lands after its start, for `region` (the planning region) and the kind
## of bake: a district (its region keeps the outline's bounds) lands its planning bake after
## `NavBakeConfig.district_frames` and an avoid map's (`avoid`) after `NavBakeConfig.avoid_frames`;
## a lone house, either, after `NavBakeConfig.house_frames`. `ring` is the planning ring's bake
## (`NavBakeConfig.ring_frames`).
static func frames_for(region: NavigationRegion3D, avoid := false, ring := false) -> int:
	var bounds: Rect2 = region.get_meta(NavBuilder.BOUNDS_META, Rect2())
	if not bounds.has_area():
		return NavBakeConfig.house_frames
	if ring:
		return NavBakeConfig.ring_frames
	return NavBakeConfig.avoid_frames if avoid else NavBakeConfig.district_frames


## Bake `job` (`NavSource.job`; `origin` is the region's offset) on a worker thread; on the game
## frame `frames` after the thread's start (see `frames_for`), assign the polygon to `region` and
## call `landed`. The thread starts now, or, with no place free, when one is (the class doc). Held
## weakly: a region freed meanwhile is left alone (a lambda that captures a node freed before it
## runs logs an engine error: a world torn down mid-bake), `landed` is still called, and it holds
## no place; a waiting one whose region is gone is never started. A job marked `urgent` (the
## planning ring's) takes no place and is a high-priority task, one a pool whose normal threads are
## busy with other bakes still runs: 14 ms of thread that waited 46 ms behind three district bakes,
## and the frame that landed it with it. A job may also carry:
## - `gather`: returns `{ poly, source }`, called as the thread starts (a waiting avoid bake is made
##   from the planning source as it is then);
## - `wanted` and `dropped`: asked when a place is free for it: false drops the bake (never started,
##   `dropped` called instead of `landed`).
## Returns the bake, to read `was_late` once it has landed.
static func start(
	region: NavigationRegion3D,
	job: Dictionary,
	origin: Vector2,
	landed: Callable,
	frames: int,
) -> NavBake:
	var bake := NavBake.new()
	bake._job = job.duplicate()
	bake._job["origin"] = origin
	bake._region_ref = weakref(region)
	bake._landed = landed
	bake._frames = frames
	bake._tree = Engine.get_main_loop() as SceneTree
	if bake._tree == null:
		bake._launch()
		bake._land()
		return bake
	if not _exit_hooked:
		_exit_hooked = true
		bake._tree.root.tree_exiting.connect(_finish_all)
	if bake._job.get("urgent", false):
		bake._launch()
	else:
		NavTurns.wait(bake)
		NavTurns.admit(_flying)
	return bake


## Whether the bake is one of the `NavBakeConfig.at_once` between start and landing: not the
## urgent ring's, and not one whose region is gone (a world torn down holds no place).
func holds_place() -> bool:
	return standing() and not _job.get("urgent", false)


## Whether the bake's region is still there: neither freed nor queued to be.
func standing() -> bool:
	var region := _region_ref.get_ref() as NavigationRegion3D
	return region != null and not region.is_queued_for_deletion()


## A waiting bake's turn has come (`NavTurns`): start its thread, unless its region is gone
## (`landed` is called) or its asker has left it (`start`'s `wanted`: `dropped` is).
func take_turn() -> void:
	if not standing():
		_landed.call()
	elif _job.has("wanted") and not _job["wanted"].call():
		_job["dropped"].call()
	else:
		_launch()


## Start the thread (and, with a tree, the count to the landing).
func _launch() -> void:
	if _job.has("gather"):
		_job.merge(_job["gather"].call(), true)
	started_total += 1
	var source: NavigationMeshSourceGeometryData2D = _job["source"]
	var origin: Vector2 = _job["origin"]
	var poly: NavigationPolygon = _job["poly"]
	var made := _mesh
	_task = WorkerThreadPool.add_task(func() -> void:
		NavSource.bake_polygon(poly, source, origin)
		made.append(NavPlan.mesh_of(poly)), _job.get("urgent", false), "nav bake")
	if _tree != null:
		_flying.append(self)
		_tree.physics_frame.connect(_on_physics_frame)


## Take every bake still in flight in at once (the game is closing: no thread is left running, and
## a waiting one is never started).
static func _finish_all() -> void:
	NavTurns.forget()
	for bake in _flying.duplicate():
		bake._land()


## Land once the frame has come.
func _on_physics_frame() -> void:
	if _due < 0:
		_due = GameClock.frame() + _frames - 1  # this is already the step after the start
	if GameClock.frame() >= _due and not landing_taken():
		take_landing()
		_land()


## Whether a landing (a bake's, or a steering burst's: `NavTileBurst`) has taken this `GameClock`
## frame: each assigns polygons and so makes its map synchronise, and the frame that holds two
## pays both. A landing due on a frame that is taken waits for the next.
static func landing_taken() -> bool:
	return _landed_frame == GameClock.frame()


## Take this `GameClock` frame for a landing.
static func take_landing() -> void:
	_landed_frame = GameClock.frame()


## Wait for the thread (it is not, but when it is late), then take its polygon in.
func _land() -> void:
	if _task < 0:
		return
	if _tree != null and _tree.physics_frame.is_connected(_on_physics_frame):
		_tree.physics_frame.disconnect(_on_physics_frame)
	_flying.erase(self)
	if not WorkerThreadPool.is_task_completed(_task):
		was_late = true
		late_total += 1
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	landed_total += 1
	var target := _region_ref.get_ref() as NavigationRegion3D
	if target != null:
		NavPlan.assign(target, _job["poly"], _mesh[0] if not _mesh.is_empty() else null)
	_landed.call()
	NavTurns.admit(_flying)
