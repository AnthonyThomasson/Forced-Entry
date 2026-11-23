extends GameTest
## A district's steering tile is baked on a worker thread (#194): the main thread gathers the
## tile's source (`NavTiles.prepare`) and pays no voxel bake (about 2 ms of the ~3.5 ms a tile took
## on the main thread), and the tile takes its polygon only when the burst lands (`NavTiles.land`).
## The polygon is the one a bake on the main thread makes from the same source, and the sync seam
## (`NavTiles.rebake`, many tiles baked as one group on the pool) makes the same polygons as the
## tiles one at a time.

const SEED := 7
## A character stands this far (px) in from the corner of the streets' rect.
const CORNER_IN := 100.0

var _district: Node2D
var _region: NavigationRegion2D


func describe() -> Dictionary:
	return {
		"name": "A steering tile's bake runs on a worker thread and makes the same polygon",
		"description": "NavTiles.prepare starts the bake on the worker pool and leaves the tile "
			+ "as it was; land gives it the polygon, vertex for vertex the one a main-thread "
			+ "bake of the same source makes; a group re-bake equals the tiles baked singly.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)
	s.actor(&"q", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_district = t.world.get("district") as Node2D
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var site := NavBuilder.site_of(_region, _district, WorldGen.district_rooms(_district))
	var front := WorldGen.district_bounds(_district).position + Vector2(CORNER_IN, CORNER_IN)
	t.actor(&"p").global_position = front
	t.actor(&"q").global_position = front + Vector2(900, 0)
	await t.frames(3)
	var due := NavTiles.due_tiles(
		_region,
		site,
		NavBuilder.furniture_holes(_district),
		NavBuilder.character_holes(_district.get_parent()),
	)
	if not t.require(due.size() >= 2, "premise: the characters made tiles due (%d)" % due.size()):
		return
	var parsed := NavTiles.parse_for(_region, site, due)
	var before := NavTiles.threaded_total
	var tile := due[0]["tile"] as NavigationRegion2D
	var polygon := tile.navigation_polygon
	var held := NavTiles.prepare(site, due[0], parsed)
	if not t.require(held != null, "premise: the first due tile was started"):
		return
	t.expect_eq(NavTiles.threaded_total, before + 1, "the bake was started on a worker thread")
	t.check(held.task >= 0, "the held bake names its pool task")
	t.expect_eq(tile.navigation_polygon, polygon, "the tile is as it was until the burst lands")
	NavTiles.land([held])
	t.expect_eq(held.task, -1, "landing joined the task")
	t.check(tile.navigation_polygon != polygon, "the tile took a polygon when the burst landed")
	var again := _on_main_thread(tile, site, held.walls, held.holes)
	var poly := held.poly
	t.expect_eq(poly.vertices, again.vertices, "the threaded bake's vertices are the main thread's")
	t.expect_eq(poly.get_polygon_count(), again.get_polygon_count(), "and its polygons")
	_group_matches_singles(t, site)
	_late_task_is_joined_first(t)


## The tile `held` was baked for, baked here from the same source on the calling thread.
func _on_main_thread(
	tile: NavigationRegion2D,
	site: NavSite,
	walls: Dictionary,
	holes: Array,
) -> NavigationPolygon:
	var job := NavSource.job(site, holes, [], walls)
	var nav_poly: NavigationPolygon = job["poly"]
	nav_poly.baking_rect = (tile.get_meta(NavTiles.RECT_META) as Rect2).grow(NavTiles.BORDER)
	nav_poly.border_size = NavTiles.BORDER
	return NavSource.bake(job, site.house.position)


## The tiles due re-baked as a group (`NavTiles.rebake`) hold the raw polygons a bake of
## each of them alone makes.
func _group_matches_singles(t: TestContext, site: NavSite) -> void:
	var tiles := NavBuilder.steering_regions(_region)
	var baked := NavTiles.rebake(
		_region,
		site,
		NavBuilder.furniture_holes(_district),
		NavBuilder.character_holes(_district.get_parent()),
	)
	if not t.require(baked >= 2, "premise: the group re-bake baked several tiles (%d)" % baked):
		return
	var matched := 0
	for tile in tiles:
		if not tile.has_meta(NavTiles.HOLES_META):
			continue
		var raw: NavigationPolygon = tile.get_meta(NavSeams.RAW_META)
		var single := _on_main_thread(
			tile,
			site,
			NavSource.walls(tile.get_meta(NavTiles.WALLS_META)),
			tile.get_meta(NavTiles.HOLES_META),
		)
		if (single.vertices == raw.vertices
				and single.get_polygon_count() == raw.get_polygon_count()):
			matched += 1
	t.check(
		matched >= baked,
		"%d tile(s) of the group equal a lone bake (baked %d)" % [matched, baked],
	)


## A task still running when its burst lands is joined before its record is touched: `land` returns
## only with the task done and `task` cleared (not before, which let the main thread write the
## record a running worker could read), and `late_total` counts it.
func _late_task_is_joined_first(t: TestContext) -> void:
	var done := [false]
	var bake := NavTileBake.new()
	bake.task = WorkerThreadPool.add_task(func() -> void:
		OS.delay_msec(250)
		done[0] = true, true, "late nav tile bake")
	var late := NavTiles.late_total
	NavTiles.land([bake])
	t.check(done[0], "land returned only when the late task was done")
	t.expect_eq(bake.task, -1, "its task was cleared after the join")
	t.expect_eq(NavTiles.late_total, late + 1, "the late task was counted")
