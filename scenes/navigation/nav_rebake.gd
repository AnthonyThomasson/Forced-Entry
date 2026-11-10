class_name NavRebake extends RefCounted
## Navigation domain: the re-bakes `nav_updater.gd` drives, from footprints it measured once for the
## tick. The planning region is baked on a worker thread (`NavBake`), so a frame never pays for it,
## and its ring with it, and lands on a fixed physics frame after it starts; the steering region (or
## a district's tiles) is baked at once.
## `NavBuilder.rebake_async` and `rebake_steering` are the test-facing seams that measure their own
## footprints and come here.


## Re-bake the planning region of `site` from the furniture footprints already measured this frame
## (`NavBuilder.furniture_holes`): the source geometry is gathered on the main thread now (the walls
## are `parsed` when the caller has parsed them this frame), the bake runs in the background and the
## polygon is assigned to `region` once it is done, when `done` is called. A region freed meanwhile
## is left alone. `done` is called even when there is nothing to bake. Returns the bakes started
## (`NavBake`: the planning region's, then the ring's; none when there is nothing to bake).
static func planning(
	region: NavigationRegion2D,
	site: NavSite,
	furniture: Array,
	done: Callable,
	parsed: Dictionary = {},
) -> Array[NavBake]:
	var job := NavSource.job(site, furniture, [], parsed)
	# The planning ring is re-baked with it, from the same footprints and walls.
	var ring := {} if job.is_empty() else NavRing.job(region, site, furniture, parsed)
	return swap(region, site, job, ring, done)


## Take a gathered planning re-bake in: `job` (`NavSource.job`) and the ring's `ring` are kept as
## the source of the next avoid map, then baked on a worker thread, each assigned to its region on
## the fixed frame it lands on (`NavBake`), and `done` is called once both have. The one place a
## finished gather becomes visible: until it, every read sees the previous map. `done` is called
## even when there is nothing to bake. Returns the bakes started (the planning region's, then the
## ring's).
static func swap(
	region: NavigationRegion2D,
	site: NavSite,
	job: Dictionary,
	ring: Dictionary,
	done: Callable,
) -> Array[NavBake]:
	var bakes: Array[NavBake] = []
	if job.is_empty():
		if done.is_valid():
			done.call()
		return bakes
	NavSource.remember(region, job)
	var waiting := [1 if ring.is_empty() else 2]
	var landed := func() -> void:
		waiting[0] -= 1
		if waiting[0] == 0 and done.is_valid():
			done.call()
	bakes.append(_bake_async(
		region, job, site.house.position, landed, NavBake.frames_for(region)))
	if not ring.is_empty():
		bakes.append(_bake_async(
			NavRing.region_of(region), ring, site.house.position, landed,
			NavBake.frames_for(region, false, true),
		))
	return bakes


## Re-bake the steering region of `site` from footprints already measured this frame: `furniture`
## (`NavBuilder.furniture_holes`) and `characters` (`NavBuilder.character_holes`). A district bakes
## its tiles (`NavTiles.rebake`). Does nothing when the region has no steering child.
static func steering(
	region: NavigationRegion2D,
	site: NavSite,
	furniture: Array,
	characters: Array,
	parsed: Dictionary = {},
) -> void:
	if site.bounds.has_area():
		NavTiles.rebake(region, site, furniture, characters, parsed)
		return
	var steering_region := NavBuilder.steering_region(region)
	if steering_region == null:
		return
	var job := NavSource.job(site, furniture, characters, parsed)
	if not job.is_empty():
		steering_region.navigation_polygon = NavSource.bake(job, site.house.position)


## `job` (`NavSource.job`) baked on a worker thread and assigned to `region` on the physics frame
## `frames` after this call, then `landed` called (`NavBake`: not when the thread finishes, so the
## frame is the same every run). Returns the bake.
static func _bake_async(
	region: NavigationRegion2D,
	job: Dictionary,
	origin: Vector2,
	landed: Callable,
	frames: int,
) -> NavBake:
	return NavBake.start(region, job, origin, landed, frames)
