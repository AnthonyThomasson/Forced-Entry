class_name NavGather extends RefCounted
## Navigation domain: a district's planning re-bake gathered a step at a time, so no frame pays for
## all of it (`nav_updater.gd` runs a step a physics frame). The gather is `NavSource.job` of the
## district's planning region and `NavRing.job` of its ring, from the footprints the tick measured:
## the walls (the towers a moved piece is near, parsed again) and the furniture holes fused. The
## fusing is nine tenths of the cost and reads nothing of the tree, so it runs on worker threads
## (`NavFuse`: the footprints taken to the bake's frame, fused, snapped and simplified, all there),
## the district's started by the first step and the ring's by the second (the ring's holes are
## binned first), both high-priority tasks, and each waited for by the step that needs it,
## `FUSE_STEPS` later; a thread that has not even started by then is not waited for: the step fuses
## on the main thread. What is left on the main thread is the walls, the ring's bin, and a step each
## for
## the district's job and the ring's (the source's walls, the prepared outlines added). It builds a
## second buffer, a pair of jobs nothing reads until `NavRebake.swap` takes it in whole, and the
## finished pair equals what a gather at once makes (`navigation/sliced_rebake_matches_whole`).

## The steps the fusing is given: the worker has this many physics frames to fuse the holes before
## the district's job needs them (a fixed count, so the planning bake starts on the same frame
## whatever the thread's wall-clock is). With the walls', the district's and the ring's steps, a
## gather takes `FUSE_STEPS + 3` steps, a physics frame each: seven frames from the tick's own, the
## swap in the last step's.
const FUSE_STEPS := 4

## How many gathers found the fusing not done when its frame came since the process began: the
## step waited for the thread (which holds the frame for the rest of its run), or the thread had
## not started and the step fused itself (`inline_total` of them,
## `navigation/fuse_without_a_thread`).
static var late_total := 0
## How many of those the step fused on the main thread, the thread not having started.
static var inline_total := 0

## The planning job and the ring's (`NavSource.job`; {} with no ring) once `step` has returned true.
var job: Dictionary = {}
var ring: Dictionary = {}
var _region: NavigationRegion3D
var site: NavSite
var _before: Array
var furniture: Array
var _walls: Dictionary = {}
var _fuse := NavFuse.new()
var _ring_reach: Dictionary = {}
var _ring_fuse := NavFuse.new()
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
		NavFuse.reap()
		_fuse.start(furniture, true, site.house.position)
	elif _step == 1:
		_ring_reach = NavRing.reach_of(_region, site, furniture, _walls)
		if not _ring_reach.is_empty():
			_ring_fuse.start(_ring_reach["holes"], true, site.house.position)
	elif _step <= FUSE_STEPS:
		pass  # the workers fuse; the frame is the threads'
	elif _step == FUSE_STEPS + 1:
		_join(_fuse)
		job = NavSource.base(site, _walls)
		if not job.is_empty():
			NavSource.add_prepared(job["source"], _fuse.prepared)
	else:
		_join(_ring_fuse)
		ring = NavRing.finish(_ring_reach, _ring_fuse.prepared)
		return true
	_step += 1
	return false


## Drop the gather before its end (the match is gone): no thread is left running.
func abandon() -> void:
	_fuse.abandon()
	_ring_fuse.abandon()


## Have `fuse` done (it is by now, but when its thread is late or never started).
func _join(fuse: NavFuse) -> void:
	match fuse.join():
		NavFuse.Found.WAITED:
			late_total += 1
		NavFuse.Found.INLINE:
			late_total += 1
			inline_total += 1
