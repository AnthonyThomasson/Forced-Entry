extends GameTest
## A district's planning re-bake is gathered a few frames at a time and swapped in whole (#192,
## rule 26): after a piece is shoved, the tick (a few physics frames: `NavTick`) re-bakes the
## steering tiles and the planning gather runs over at least two and at most `MOST_FRAMES` physics
## frames from the timer, during which every read (the region's polygon, the map's iteration, a
## route) still sees the previous map. The map it swaps in equals a whole re-bake of the same world,
## the ring too; a piece shoved while the gather runs is caught by the next tick; and a region freed
## mid-gather leaves nothing running.
## What marks the swap is the region's remembered source `version` (`NavSource.remember`), which
## counts finished gathers, and then the planning region's polygon, assigned when the bake lands.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SEED := 7
## The most physics frames the gather may take, from the timer to the swap: the district's tick (the
## footprints read, the characters', the outlines binned, the tiles checked: nine of this district's
## 857 pieces) and the gather's own seven.
const MOST_FRAMES := 34
## How long (sim s) a bake may take to land: it runs on the server's worker thread in real time.
const WAIT := 12.0

var _region: NavigationRegion3D
var _district: Node2D
var _timer: Timer


func describe() -> Dictionary:
	return {
		"name": "A district's sliced planning re-bake equals a whole one",
		"description": "A piece is shoved; the planning gather takes two to 34 frames with "
			+ "the previous map answering throughout, then the map equals a whole re-bake.",
		"tags": ["navigation", "district", "rebake", "perf"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_region = t.world.find_children("NavRegion", "NavigationRegion3D", true, false)[0]
	_district = t.world.district
	_timer = t.world.get_node("NavUpdater/RebakeTimer") as Timer
	for body in PlanProbe.pieces_under(_district):
		var lead := TwinSpace.leader_of(body)
		if lead != null:  # nothing but the shoves below moves
			lead.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			lead.freeze = true
	var pieces := _solid_pieces(_district)
	if not t.require(pieces.size() >= 2, "premise: the district has solid pieces"):
		return
	_timer.stop()  # the ticks are driven here
	var updater := _timer.get_parent()
	await t.until(
		func() -> bool: return not updater.busy(),
		8.0,
	)  # a cold tick and its bake end first
	await t.seconds(1.0)  # whatever the first ticks started lands
	await _check_sliced(t, pieces)
	await _check_next_tick(t)
	_check_equals_whole(t)
	await _check_freed_mid_gather(t, pieces[0])


## A piece shoved: the gather takes two to `MOST_FRAMES` frames and the previous map answers
## throughout.
func _check_sliced(t: TestContext, pieces: Array[Node2D]) -> void:
	var map := _region.get_navigation_map()
	var held := NavPlan.polygon_of(_region)
	var version := _version()
	var iteration := NavPlan.iteration(map)
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
				and NavPlan.polygon_of(_region) == held
				and NavPlan.iteration(map) == iteration
				and NavBuilder.route(map, from, to) == route_before
			)
	t.check(
		_version() == version + 1 and frames >= 2 and frames <= MOST_FRAMES,
		"the gather ends in two to %d frames (took %d)" % [MOST_FRAMES, frames],
	)
	t.check(seen_previous, "until then the region, the map and a route are the previous map's")
	t.check(
		await t.until(func() -> bool: return NavPlan.polygon_of(_region) != held, WAIT),
		"the planning region is re-baked after the first shove",
	)


## The piece shoved while the gather ran was left for the next tick, which gathers it.
func _check_next_tick(t: TestContext) -> void:
	var version := _version()
	var held := NavPlan.polygon_of(_region)
	var held_ring := NavPlan.polygon_of(NavRing.region_of(_region))
	_timer.timeout.emit()
	t.check(
		await t.until(func() -> bool: return _version() >= version + 1, WAIT),
		"a piece shoved while a gather ran is gathered by the next tick",
	)
	t.check(
		await t.until(func() -> bool: return NavPlan.polygon_of(_region) != held, WAIT),
		"and its bake lands on the planning region",
	)
	t.check(
		await t.until(
			func() -> bool: return NavPlan.polygon_of(NavRing.region_of(_region)) != held_ring,
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
		_same_mesh(NavPlan.polygon_of(_region), whole),
		"the swapped-in map is a whole re-bake's",
	)
	var ring := NavRing.job(_region, site, furniture, {})
	var whole_ring := NavSource.bake(ring, _district.position)
	t.check(
		_same_mesh(NavPlan.polygon_of(NavRing.region_of(_region)), whole_ring),
		"and so is the ring",
	)


## A region freed while a gather runs: the updater stops and nothing is logged.
func _check_freed_mid_gather(t: TestContext, piece: Node2D) -> void:
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


## Shove `piece` by `by` px: its 3D body (the twin the holes are cut from, which a footprint moved
## by hand reaches only up to `TwinSpace.PARK_SPREAD` frames later) and its footprint with it.
func _shove(piece: Node2D, by: Vector2) -> void:
	TwinSpace.leader_of(piece).global_position += PlanSpace.lift(by)
	piece.global_position += by


func _same_mesh(a: NavigationPolygon, b: NavigationPolygon) -> bool:
	if a.get_polygon_count() != b.get_polygon_count() or a.get_vertices() != b.get_vertices():
		return false
	for i in a.get_polygon_count():
		if a.get_polygon(i) != b.get_polygon(i):
			return false
	return true


## The district's free pieces: a rigid body led by a 3D body of the twin space (the holes are cut
## from it: a footprint moved by hand sends it there, as an anchored piece's twin is not sent).
func _solid_pieces(district: Node2D) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for body in PlanProbe.pieces_under(district):
		if TwinSpace.leader_of(body) != null:
			out.append(body)
		if out.size() == 2:
			break
	return out
