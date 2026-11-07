class_name NavGather extends RefCounted
## Navigation domain: a district's planning re-bake gathered a step at a time, so no frame pays for
## all of it (`nav_updater.gd` runs a step a physics frame). The gather is `NavSource.job` of the
## district's planning region and `NavRing.job` of its ring, from the footprints the tick measured:
## the walls (the towers a moved piece is near, parsed again), the furniture holes fused in
## `FUSE_STEPS` chunks (the fusing is nine tenths of the cost), the district's job, then the ring's.
## It builds a second buffer, a pair of jobs nothing reads until `NavRebake.swap` takes it in whole,
## and the finished pair equals what a gather at once makes
## (`navigation/sliced_rebake_matches_whole`).

## The chunks the furniture holes are fused in, a step each. With the walls', the district's and the
## ring's steps, a gather takes `FUSE_STEPS + 3` steps, a physics frame each: seven frames from
## the tick's own, the swap in the last step's.
const FUSE_STEPS := 4

## The planning job and the ring's (`NavSource.job`; {} with no ring) once `step` has returned true.
var job: Dictionary = {}
var ring: Dictionary = {}
var _region: NavigationRegion2D
var site: NavSite
var _before: Array
var furniture: Array
var _walls: Dictionary = {}
var _outlines: Array = []
var _fusion := NavUnion.new()
var _fused := 0
var _step := 0


## A gather of `region`'s planning bake for `site`, after the furniture went from `before` to
## `furniture` (`NavBuilder.furniture_holes`).
func _init(
	region: NavigationRegion2D,
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
	elif _step <= FUSE_STEPS:
		var chunk := ceili(float(_outlines.size()) / FUSE_STEPS)
		_fusion.add_all(_outlines.slice(_fused, _fused + chunk))
		_fused += chunk
	elif _step == FUSE_STEPS + 1:
		job = NavSource.base(site, _walls)
		if not job.is_empty():
			NavSource.finish_holes(job["source"], _fusion.result())
	else:
		ring = NavRing.job(_region, site, furniture, _walls)
		return true
	_step += 1
	return false
