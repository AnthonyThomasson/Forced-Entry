extends GameTest
## A district's planning re-bake is gathered a few frames at a time and swapped in whole (#192,
## rule 26): after a piece is shoved, the tick re-bakes the steering tiles at once and the planning
## gather runs over at least two and at most eight physics frames, during which every read (the
## region's polygon, the map's iteration, a route) still sees the previous map. The map it swaps in
## equals a whole re-bake of the same world, the ring too; a piece shoved while the gather runs is
## caught by the next tick; and a region freed mid-gather leaves nothing running.
## What marks the swap is the region's remembered source `version` (`NavSource.remember`), which
## counts finished gathers, and then the planning region's polygon, assigned when the bake lands.

const SEED := 7
## The most physics frames the gather may take, from the tick to the swap.
const MOST_FRAMES := 8
## How long (sim s) a bake may take to land: it runs on the server's worker thread in real time.
const WAIT := 12.0

var _region: NavigationRegion2D
var _district: Node2D
var _timer: Timer


func describe() -> Dictionary:
	return {
		"name": "A district's sliced planning re-bake equals a whole one",
		"description": "A piece is shoved; the planning gather takes two to eight frames with the "
			+ "previous map answering throughout, then the map equals a whole re-bake.",
		"tags": ["navigation", "district", "rebake", "perf"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_district = t.world.district
	_timer = t.world.get_node("NavUpdater/RebakeTimer") as Timer
	for body in _district.find_children("*", "RigidBody2D", true, false):
		body.freeze = true  # nothing but the shoves below moves
	var pieces := _solid_pieces(_district)
	if not t.require(pieces.size() >= 2, "premise: the district has solid pieces"):
		return
	_timer.stop()  # the ticks are driven here
	await t.seconds(1.0)  # whatever the first ticks started lands
	await _check_sliced(t, pieces)
	await _check_next_tick(t)
	_check_equals_whole(t)
	await _check_freed_mid_gather(t, pieces[0])


## A piece shoved: the gather takes two to `MOST_FRAMES` frames and the previous map answers
## throughout.
func _check_sliced(t: TestContext, pieces: Array[RigidBody2D]) -> void:
	var map := _region.get_navigation_map()
	var held := _region.navigation_polygon
	var version := _version()
	var iteration := NavigationServer2D.map_get_iteration_id(map)
	var rooms := WorldGen.district_rooms(_district)
	var from: Vector2 = rooms[0]["rect"].get_center()
	var to: Vector2 = rooms[3]["rect"].get_center()
	var route_before := NavBuilder.route(map, from, to)
	_shove(pieces[0], Vector2(60.0, 0.0))
	await t.frames(1)
	_timer.timeout.emit()
	var frames := 0
	var seen_previous := true
	while _version() == version and frames < MOST_FRAMES + 4:
		await t.frames(1)
		frames += 1
		if frames == 2 and _version() == version:
			# A piece shoved while the gather runs, and a tick that meets it: it waits.
			_shove(pieces[1], Vector2(0.0, 60.0))
			_timer.timeout.emit()
		if _version() == version:
			seen_previous = (
				seen_previous
				and _region.navigation_polygon == held
				and NavigationServer2D.map_get_iteration_id(map) == iteration
				and NavBuilder.route(map, from, to) == route_before
			)
	t.check(
		_version() == version + 1 and frames >= 2 and frames <= MOST_FRAMES,
		"the gather ends in two to %d frames (took %d)" % [MOST_FRAMES, frames],
	)
	t.check(seen_previous, "until then the region, the map and a route are the previous map's")
	t.check(
		await t.until(func() -> bool: return _region.navigation_polygon != held, WAIT),
		"the planning region is re-baked after the first shove",
	)


## The piece shoved while the gather ran was left for the next tick, which gathers it.
func _check_next_tick(t: TestContext) -> void:
	var version := _version()
	var held := _region.navigation_polygon
	var held_ring := NavRing.region_of(_region).navigation_polygon
	_timer.timeout.emit()
	t.check(
		await t.until(func() -> bool: return _version() >= version + 1, WAIT),
		"a piece shoved while a gather ran is gathered by the next tick",
	)
	t.check(
		await t.until(func() -> bool: return _region.navigation_polygon != held, WAIT),
		"and its bake lands on the planning region",
	)
	t.check(
		await t.until(
			func() -> bool: return NavRing.region_of(_region).navigation_polygon != held_ring,
			WAIT,
		),
		"and on the ring",
	)


## The map and the ring equal a whole re-bake of the world as it stands.
func _check_equals_whole(t: TestContext) -> void:
	var rooms := WorldGen.district_rooms(_district)
	var site := NavBuilder.site_of(_region, _district, rooms)
	var furniture := NavBuilder.furniture_holes(_district)
	var whole := NavSource.bake(NavSource.job(site, furniture), _district.position)
	t.check(
		_same_mesh(_region.navigation_polygon, whole),
		"the swapped-in map is a whole re-bake's",
	)
	var ring := NavRing.job(_region, site, furniture, {})
	var whole_ring := NavSource.bake(ring, _district.position)
	t.check(
		_same_mesh(NavRing.region_of(_region).navigation_polygon, whole_ring),
		"and so is the ring",
	)


## A region freed while a gather runs: the updater stops and nothing is logged.
func _check_freed_mid_gather(t: TestContext, piece: RigidBody2D) -> void:
	_shove(piece, Vector2(-40.0, 0.0))
	await t.frames(1)
	_timer.timeout.emit()
	await t.frames(2)
	_region.queue_free()
	await t.frames(MOST_FRAMES + 2)
	t.check(
		not (t.world.get_node("NavUpdater") as Node).is_physics_processing(),
		"the region was freed mid-gather and the updater dropped the gather",
	)


func _version() -> int:
	return int((_region.get_meta(NavBuilder.SOURCE_META) as Dictionary)["version"])


func _shove(piece: RigidBody2D, by: Vector2) -> void:
	piece.freeze = true  # a free body is put back by the next physics step
	piece.global_position += by


func _same_mesh(a: NavigationPolygon, b: NavigationPolygon) -> bool:
	if a.get_polygon_count() != b.get_polygon_count() or a.get_vertices() != b.get_vertices():
		return false
	for i in a.get_polygon_count():
		if a.get_polygon(i) != b.get_polygon(i):
			return false
	return true


## The district's solid pieces: a rigid body with a collider.
func _solid_pieces(district: Node2D) -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for body in district.find_children("*", "RigidBody2D", true, false):
		if not body.find_children("*", "CollisionShape2D", true, false).is_empty():
			out.append(body)
		if out.size() == 2:
			break
	return out
