extends GameTest
## The worst-frames report's navigation counters (`tests/_perf/frame_report.gd`, `perf.md`) on a
## live district: each is seen in a frame where its work ran. A re-bake of the steering map bakes
## the tiles a moved character touched (`tile_bakes`, as many as tiles whose polygon was replaced);
## a planning re-bake starts (`bakes`) and lands (`landings`) on its later frame; a first ask for an
## avoid map starts one (`avoid_starts`), and one asked again after the planning bake changed
## re-bakes (`avoid_rebakes`). Interface 9.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const SEED := 7
const CORNER_IN := 100.0
## The hole an avoid map is asked with (a doorway's view, world space).
const HOLE := [Vector2(380, 100), Vector2(420, 100), Vector2(420, 400), Vector2(380, 400)]
## The measured frames the actions are made in, and a margin the counted frame may differ by (a
## synchronous call at the start of frame `i` is in the rise read before the next sample).
const ACT_AT := 3
const NEAR := 1

var _district: Node2D
var _region: NavigationRegion2D
var _rooms: Array
var _tiles: Array
## How many tiles' polygons the steering re-bake the window made replaced (the independent count).
var _replaced := 0


func describe() -> Dictionary:
	return {
		"name": "The worst-frames report counts the nav tile bakes, landings and avoid maps",
		"description": "In a district a steering re-bake, a planning re-bake and its landing and "
			+ "an avoid map's start and re-bake are each counted in a frame the work ran in.",
		"tags": ["navigation", "district", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	_district = t.world.get("district") as Node2D
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_rooms = WorldGen.district_rooms(_district)
	_tiles = NavBuilder.steering_regions(_region)
	var logging := GameLog.enabled
	GameLog.enabled = true
	await _steering_tiles(t)
	await _planning_and_avoid(t)
	GameLog.enabled = logging


## A character moved 300 px: the steering re-bake bakes the tiles round it, and the frame's count
## is the tiles whose polygon was replaced.
func _steering_tiles(t: TestContext) -> void:
	var streets := WorldGen.district_bounds(_district)
	var front := streets.position + Vector2(CORNER_IN, CORNER_IN)
	var puppet: Node2D = t.actor(&"p")
	puppet.global_position = front
	NavBuilder.rebake_steering(_region, _district, _rooms)  # takes the character in
	await t.frames(2)
	var stats := await Perf.frame_stats(
		t, 8, func(i: int) -> void:
			if i == ACT_AT:
				puppet.global_position = front + Vector2(300, 0)
			if i == ACT_AT + 1:
				_replaced = _rebake_steering_counting()
	)
	t.check(_replaced >= 1, "premise: the re-bake replaced a tile (%d)" % _replaced)
	var frames := _frames_with(stats["ran"], "tile_bakes")
	t.check(
		frames.size() == 1 and absi(frames[0] - (ACT_AT + 1)) <= NEAR,
		"the tiles baked are counted in the frame of the re-bake (counted in %s)" % str(frames),
	)
	t.expect_eq(
		_sum(stats["ran"], "tile_bakes"), _replaced,
		"as many tiles baked as tiles' polygons replaced",
	)


## A planning re-bake, an avoid map asked and then asked again once the planning bake changed.
func _planning_and_avoid(t: TestContext) -> void:
	var again := ACT_AT + NavBakeConfig.district_frames + 2
	var stats := await Perf.frame_stats(
		t, again + NavBakeConfig.district_frames + 6, func(i: int) -> void:
			if i == ACT_AT:
				NavBuilder.avoid_map(_region, "counted", [PackedVector2Array(HOLE)])
			if i == ACT_AT + 2:
				# The planning bake's source is kept as it starts, so the map made above is older.
				NavBuilder.rebake_async(
					_region, _district, _rooms, NavBuilder.AGENT_RADIUS, func() -> void: pass,
				)
			if i == again:
				NavBuilder.avoid_map(_region, "counted", [PackedVector2Array(HOLE)])
	)
	var ran: Array = stats["ran"]
	var started := _frames_with(ran, "bakes")
	t.check(
		started.size() >= 2 and absi(started[0] - ACT_AT) <= NEAR,
		"the avoid bake and then the planning bakes are counted when started (counted in %s)"
			% str(started),
	)
	var avoided := _frames_with(ran, "avoid_starts")
	t.check(
		avoided.size() == 1 and absi(avoided[0] - ACT_AT) <= NEAR,
		"the avoid map's first ask is counted in its frame (counted in %s)" % str(avoided),
	)
	var landed := _frames_with(ran, "landings")
	t.check(
		not landed.is_empty() and landed[0] > ACT_AT + NEAR,
		"a bake's landing is counted in a frame after its start (counted in %s)" % str(landed),
	)
	var rebaked := _frames_with(ran, "avoid_rebakes")
	t.check(
		rebaked.size() == 1 and absi(rebaked[0] - again) <= NEAR,
		"the avoid map asked after the planning bake changed re-bakes (counted in %s)"
			% str(rebaked),
	)
	t.check(
		_sum(ran, "landings") >= 3,
		"the planning bakes and both avoid bakes landed in the window (%d landings)"
			% _sum(ran, "landings"),
	)


## Re-bake the steering map; how many tiles have a polygon other than before.
func _rebake_steering_counting() -> int:
	var before: Array = _tiles.map(
		func(tile: NavigationRegion2D) -> NavigationPolygon: return tile.navigation_polygon,
	)
	NavBuilder.rebake_steering(_region, _district, _rooms)
	var changed := 0
	for i in _tiles.size():
		if (_tiles[i] as NavigationRegion2D).navigation_polygon != before[i]:
			changed += 1
	return changed


## The frames (indexes) of `ran` in which the counter `key` rose.
func _frames_with(ran: Array, key: String) -> Array:
	var out := []
	for i in ran.size():
		if (ran[i] as Dictionary).get(key, 0) > 0:
			out.append(i)
	return out


func _sum(ran: Array, key: String) -> int:
	var total := 0
	for frame: Dictionary in ran:
		total += frame.get(key, 0)
	return total
