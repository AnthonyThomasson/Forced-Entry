class_name NavBake extends RefCounted
## Navigation domain: one re-bake's thread and its landing. The bake runs on a thread of the
## `WorkerThreadPool`, started now, and its result is taken in (welded, assigned to its region,
## `landed` called) on the physics frame `NavBakeConfig.district_frames` after the start, not when
## the thread happens to finish: the same frame every run. A thread that is not done by then is
## waited for, which holds that frame (`late` counts those). A bake in flight is kept in `_flying`
## until it lands, so nothing frees it first.

## How many bakes were still running when their frame came, since the process began.
static var late := 0
## The bakes between their start and their landing.
static var _flying: Array[NavBake] = []
## Whether the root window's exit has been hooked to finish the bakes (`_finish_all`).
static var _exit_hooked := false

## The worker-pool task baking the polygon (-1 once it has landed), the physics frame it lands on,
## the polygon, the region's offset, the region (weakly), what to call once it has landed and the
## tree whose physics frames count.
var _task := -1
var _due := 0
var _poly: NavigationPolygon
var _origin := Vector2.ZERO
var _region_ref: WeakRef
var _landed: Callable
var _tree: SceneTree


## The physics frames a bake for `region` (the planning region) lands after its start: a district's
## `NavBakeConfig.district_frames` (its region keeps the outline's bounds), a lone house's
## `NavBakeConfig.house_frames`.
static func frames_for(region: NavigationRegion2D) -> int:
	var bounds: Rect2 = region.get_meta(NavBuilder.BOUNDS_META, Rect2())
	return NavBakeConfig.district_frames if bounds.has_area() else NavBakeConfig.house_frames


## Start baking `job` (`NavSource.job`) on a worker thread; on the physics frame `frames` on (see
## `frames_for`), weld it (`origin` is the region's offset), assign it to `region` and call
## `landed`. Held weakly: a region freed meanwhile is left alone (a lambda that captures a
## node freed before it runs logs an engine error: a world torn down mid-bake), and `landed` is
## still called.
static func start(
	region: NavigationRegion2D,
	job: Dictionary,
	origin: Vector2,
	landed: Callable,
	frames: int,
) -> void:
	var bake := NavBake.new()
	bake._poly = job["poly"]
	bake._origin = origin
	bake._region_ref = weakref(region)
	bake._landed = landed
	bake._tree = Engine.get_main_loop() as SceneTree
	var source: NavigationMeshSourceGeometryData2D = job["source"]
	var poly := bake._poly
	bake._task = WorkerThreadPool.add_task(func() -> void:
		NavigationServer2D.bake_from_source_geometry_data(poly, source), false, "nav bake")
	if bake._tree == null:
		bake._land()
		return
	bake._due = Engine.get_physics_frames() + frames
	_flying.append(bake)
	bake._tree.physics_frame.connect(bake._on_physics_frame)
	if not _exit_hooked:
		_exit_hooked = true
		bake._tree.root.tree_exiting.connect(_finish_all)


## Take every bake still in flight in at once (the game is closing: no thread is left running).
static func _finish_all() -> void:
	for bake in _flying.duplicate():
		bake._land()


## Land once the frame has come.
func _on_physics_frame() -> void:
	if Engine.get_physics_frames() >= _due:
		_land()


## Wait for the thread (it is not, but when it is late), then take its polygon in.
func _land() -> void:
	if _task < 0:
		return
	if _tree != null and _tree.physics_frame.is_connected(_on_physics_frame):
		_tree.physics_frame.disconnect(_on_physics_frame)
	_flying.erase(self)
	if not WorkerThreadPool.is_task_completed(_task):
		late += 1
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var target := _region_ref.get_ref() as NavigationRegion2D
	if target != null:
		NavWeld.finish(_poly, _origin)
		target.navigation_polygon = _poly
	_landed.call()
