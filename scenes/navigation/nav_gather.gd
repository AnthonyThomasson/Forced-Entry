class_name NavGather extends RefCounted
## Navigation domain: a district's planning re-bake gathered a step at a time, so no frame pays for
## all of it (`nav_updater.gd` runs a step a physics frame). The gather is `NavSource.job` of the
## district's planning region and `NavRing.job` of its ring, from the footprints the tick measured:
## the walls (the towers a moved piece is near, parsed again), the furniture holes fused (the fusing
## is nine tenths of the cost: it reads nothing of the tree, so it runs on a worker thread, started
## by the first step as a high-priority task, so it does not queue behind the bakes in flight, and
## waited for by the one that needs it, `FUSE_STEPS` later), the district's
## job, then the ring's. It builds a second buffer, a pair of jobs nothing reads until
## `NavRebake.swap` takes it in whole, and the finished pair equals what a gather at once makes
## (`navigation/sliced_rebake_matches_whole`).

## The steps the fusing is given: the worker has this many physics frames to fuse the holes before
## the district's job needs them (a fixed count, so the planning bake starts on the same frame
## whatever the thread's wall-clock is). With the walls', the district's and the ring's steps, a
## gather takes `FUSE_STEPS + 3` steps, a physics frame each: seven frames from the tick's own, the
## swap in the last step's.
const FUSE_STEPS := 4

## How many gathers found the fusing not done when its frame came since the process began (the
## step waited for the thread, which holds the frame for the rest of its run).
static var late_total := 0

## The planning job and the ring's (`NavSource.job`; {} with no ring) once `step` has returned true.
var job: Dictionary = {}
var ring: Dictionary = {}
var _region: NavigationRegion3D
var site: NavSite
var _before: Array
var furniture: Array
var _walls: Dictionary = {}
var _outlines: Array = []
var _fusion := NavUnion.new()
var _task := -1
var _step := 0


## A gather of `region`'s planning bake for `site`, after the furniture went from `before` to
## `furniture` (`NavBuilder.furniture_holes`).
func _init(
	region: NavigationRegion3D,
	gathered_site: NavSite,
	before: Array,
	gathered_furniture: Array,
) -> void:
	_region = region
	site = gathered_site
	_before = before
	furniture = gathered_furniture


## Run the next step; true once the gather is finished and `job` and `ring` are set.
func step() -> bool:
	if _step == 0:
		_walls = NavTiles.walls_after(_region, site, _before, furniture)
		_outlines = NavSource.local_outlines(site.house.position, furniture)
		var fusion := _fusion
		var outlines := _outlines
		_task = WorkerThreadPool.add_task(
			func() -> void: fusion.add_all(outlines), true, "nav gather fuse")
	elif _step <= FUSE_STEPS:
		pass  # the worker fuses; the frame is the thread's
	elif _step == FUSE_STEPS + 1:
		_join()
		job = NavSource.base(site, _walls)
		if not job.is_empty():
			NavSource.finish_holes(job["source"], _fusion.result())
	else:
		ring = NavRing.job(_region, site, furniture, _walls)
		return true
	_step += 1
	return false


## Drop the gather before its end (the match is gone): no thread is left running.
func abandon() -> void:
	_join()


## Wait for the fusing's thread (it is done by now, but when it is late).
func _join() -> void:
	if _task < 0:
		return
	if not WorkerThreadPool.is_task_completed(_task):
		late_total += 1
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
