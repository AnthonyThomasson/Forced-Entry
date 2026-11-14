extends GameTest
## A district's steering tiles are baked at most one a physics frame and land together (#195). The
## tick found every tile a character stopped in or set off from due and baked them all in its own
## frame, and each frame that gives a tile its polygon pays a steering-map synchronisation of about
## 12 ms whatever the count. So the tick bakes the first due tile and the updater's physics step
## one more a frame, the tiles holding a moving walker first, nearest first, then the grid's order
## (`NavTiles.due_tiles`), the polygons held until the last is baked and landed in that frame
## (`NavTiles.prepare`, `land`): one synchronisation a tick, and the baking spread.
## Three puppets stop in three tiles of a row and a fourth, that stood in a tile of its own, walks
## off: five to seven tiles go due in one tick.

const SEED := 7
## A character stands this far (px) in from the corner of the streets' rect.
const CORNER_IN := 100.0
## How far (px) the stopped puppets are set along their row, and the tiles' rows apart.
const STEP := 700.0
## Physics frames to wait for the re-bake after the move, and to watch after the first bake (under
## the 45 frames of the next tick).
const WAIT_FRAMES := 60
const AFTER_FRAMES := 20

var _tiles: Array[NavigationRegion2D] = []
var _seen: Array[NavigationPolygon] = []


func describe() -> Dictionary:
	return {
		"name": "A district's steering tiles are baked one a frame and land together",
		"description": "Several characters stop in different tiles at once and one walks off: "
			+ "no physics frame bakes two tiles, and every due tile lands, all on one frame, "
			+ "within as many frames as there are tiles.",
		"tags": ["navigation", "district", "rebake", "steering"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)
	s.actor(&"a", &"puppet", Vector2.ZERO)
	s.actor(&"b", &"puppet", Vector2.ZERO)
	s.actor(&"c", &"puppet", Vector2.ZERO)
	s.actor(&"w", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	var region := t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_tiles = NavBuilder.steering_regions(region as NavigationRegion2D)
	var front := WorldGen.district_bounds(district).position + Vector2(CORNER_IN, CORNER_IN)
	var stopped: Array[Node2D] = [t.actor(&"a"), t.actor(&"b"), t.actor(&"c")]
	for i in stopped.size():
		stopped[i].global_position = front + Vector2(STEP * i, 0)
	# The walker's tile is the last of the grid's order among the due ones: the tile one row down
	# from the first stopped puppet's, at its centre so it walks a while inside it.
	var walker_tile := _tile_below(_tile_at(district, stopped[0].global_position))
	if not t.require(walker_tile != null, "premise: the row of tiles has one below it"):
		return
	var walker := t.actor(&"w")
	var centre := (walker_tile.get_meta(NavTiles.RECT_META) as Rect2).get_center()
	walker.global_position = district.to_global(centre)
	await t.seconds(2.0)  # the ticks that take them in
	_remember()
	var prepared_before := NavTiles.baked_total
	for puppet in stopped:
		puppet.global_position += Vector2(300, 0)
	t.puppet(&"w").walk(Vector2.RIGHT)
	var frames := []
	for _i in WAIT_FRAMES:
		await t.frames(1)
		frames.append({
			"prepared": NavTiles.baked_total - prepared_before,
			"landed": _changed_since_remembered(),
		})
		_remember()
		prepared_before = NavTiles.baked_total
		if _first_baked(frames) >= 0 and frames.size() - _first_baked(frames) > AFTER_FRAMES:
			break  # the next tick is 45 frames on
	_judge(t, frames)


## The index of the first of `frames` that baked a tile, -1 for none.
func _first_baked(frames: Array) -> int:
	for i in frames.size():
		if frames[i]["prepared"] > 0:
			return i
	return -1


## `frames`, one entry for each physics frame after the move (`prepared`: the tiles baked since
## the one before; `landed`: the tiles that took a polygon): at most one tile baked a frame, every
## baked tile landed on one frame, within the burst's frames of the first bake (the order the tiles
## are baked in is `tile_due_order_test.gd`'s).
func _judge(t: TestContext, frames: Array) -> void:
	var baked := 0
	var worst := 0
	var first_baked := -1
	var landing_frames := []
	var landed := 0
	for i in frames.size():
		var entry: Dictionary = frames[i]
		baked += entry["prepared"]
		worst = maxi(worst, entry["prepared"])
		if entry["prepared"] > 0 and first_baked < 0:
			first_baked = i
		if not (entry["landed"] as Array).is_empty():
			landing_frames.append(i)
			landed += (entry["landed"] as Array).size()
	if not t.require(baked >= 4, "premise: the move made at least four tiles due (%d)" % baked):
		return
	t.expect_eq(worst, 1, "no physics frame bakes more than one tile")
	t.expect_eq(
		landing_frames.size(),
		1,
		"the tiles landed on one frame (%s)" % str(landing_frames),
	)
	t.expect_eq(landed, baked, "every tile baked landed")
	t.check(
		landing_frames.size() == 1 and landing_frames[0] - first_baked <= baked - 1,
		"the burst of %d tiles landed within %d frames of its first bake (first %d, landed %s)"
			% [baked, baked, first_baked, str(landing_frames)],
	)


## Remember every tile's polygon now.
func _remember() -> void:
	_seen.clear()
	for tile in _tiles:
		_seen.append(tile.navigation_polygon)


## The indices of the tiles whose polygon is another than the one remembered.
func _changed_since_remembered() -> Array:
	var out := []
	for i in _tiles.size():
		if _tiles[i].navigation_polygon != _seen[i]:
			out.append(i)
	return out


## The tile whose rect holds `point` (a world point of `district`'s frame).
func _tile_at(district: Node2D, point: Vector2) -> NavigationRegion2D:
	var local := district.to_local(point)
	for tile in _tiles:
		if (tile.get_meta(NavTiles.RECT_META) as Rect2).has_point(local):
			return tile
	return null


## The tile one row below `tile`'s, in its column; null at the grid's bottom.
func _tile_below(tile: NavigationRegion2D) -> NavigationRegion2D:
	if tile == null:
		return null
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	for other in _tiles:
		var other_rect: Rect2 = other.get_meta(NavTiles.RECT_META)
		if (is_equal_approx(other_rect.position.x, rect.position.x)
				and is_equal_approx(other_rect.position.y, rect.end.y)):
			return other
	return null
