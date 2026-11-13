extends GameTest
## The order a district's due steering tiles are baked in (`NavTiles.due_tiles`, #195): the tiles
## that hold a moving walker first, nearest first, then the rest, equal distances in the grid's
## order; with nothing walking, the grid's order. Read from what `due_tiles` returns for the
## footprints of the moment, the updater off, so the order is what is asked for and not a log of
## what was baked.
## Three puppets stop in three tiles of a row and a fourth, that stood in a tile of its own below
## the first, walks off: tiles go due in the row and in the walker's column.

const SEED := 7
const CORNER_IN := 100.0
const STEP := 700.0
const MOVE := 300.0
## Physics frames the walker walks before the footprints are read: its speed passes the rest speed.
const WALK_FRAMES := 12

var _tiles: Array[NavigationRegion2D] = []
var _district: Node2D
var _region: NavigationRegion2D


func describe() -> Dictionary:
	return {
		"name": "Due steering tiles are ordered walker's tile, nearest, then the grid's order",
		"description": "With a walker moving in a district, due_tiles puts its own tile first "
			+ "and the rest by distance to it, ties in the grid's order; with none walking, "
			+ "the grid's order.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	s.actor(&"a", &"puppet", Vector2.ZERO)
	s.actor(&"b", &"puppet", Vector2.ZERO)
	s.actor(&"c", &"puppet", Vector2.ZERO)
	s.actor(&"w", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	if not await _stage(t):
		return
	var site := NavBuilder.site_of(_region, _district, WorldGen.district_rooms(_district))
	var furniture := NavBuilder.furniture_holes(_district)
	# Nothing walking: the grid's order.
	var still := NavBuilder.character_holes(_district.get_parent())
	_check_order(t, NavTiles.due_tiles(_region, site, furniture, still), [])
	# The walker walking: its tile first, then by distance, ties by the grid.
	t.puppet(&"w").walk(Vector2.RIGHT)
	await t.frames(WALK_FRAMES)
	var walkers := NavTiles.walking_at(_district.get_parent())
	if not t.require(walkers.size() == 1, "premise: one character walks (%d)" % walkers.size()):
		return
	var characters := NavBuilder.character_holes(_district.get_parent())
	var due := NavTiles.due_tiles(_region, site, furniture, characters, walkers)
	_check_order(t, due, walkers)
	var local := walkers[0] - _district.position
	t.check(
		not due.is_empty()
			and (due[0]["tile"].get_meta(NavTiles.RECT_META) as Rect2).has_point(local),
		"the first tile is the one that holds the walker",
	)


## Place the puppets, take them in and move the stopped ones: true when the scene is staged.
func _stage(t: TestContext) -> bool:
	await t.seconds(0.5)
	_district = t.world.get("district") as Node2D
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_tiles = NavBuilder.steering_regions(_region)
	var front := WorldGen.district_bounds(_district).position + Vector2(CORNER_IN, CORNER_IN)
	var stopped: Array[Node2D] = [t.actor(&"a"), t.actor(&"b"), t.actor(&"c")]
	for i in stopped.size():
		stopped[i].global_position = front + Vector2(STEP * i, 0)
	var below := _below(_tile_at(_district, stopped[0].global_position))
	if not t.require(below != null, "premise: the row of tiles has one below it"):
		return false
	t.actor(&"w").global_position = _district.to_global(
		(below.get_meta(NavTiles.RECT_META) as Rect2).get_center())
	await t.frames(3)
	NavBuilder.rebake_steering(_region, _district, WorldGen.district_rooms(_district))
	for puppet in stopped:
		puppet.global_position += Vector2(MOVE, 0)
	await t.frames(3)
	return true


## `due` (`due_tiles`' entries) is in order of distance from the nearest of `walkers` (world
## points) to each tile's rect, equal distances in the grid's order (`_tiles`'); with none, in the
## grid's order. Computed here from the rects, not by `NavTiles`.
func _check_order(t: TestContext, due: Array[Dictionary], walkers: Array[Vector2]) -> void:
	t.check(due.size() >= 4, "premise: at least four tiles are due (%d)" % due.size())
	var keys: Array[Array] = []
	for entry in due:
		var tile: NavigationRegion2D = entry["tile"]
		var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
		var gap := INF
		for point in walkers:
			var local := point - _district.position
			gap = minf(gap, (local.clamp(rect.position, rect.end) - local).length_squared())
		keys.append([gap, _tiles.find(tile)])
	var ordered := true
	for i in range(1, keys.size()):
		var before: Array = keys[i - 1]
		var after: Array = keys[i]
		var same_gap: bool = before[0] == after[0]
		ordered = ordered and (before[0] < after[0] or (same_gap and before[1] < after[1]))
	t.check(
		ordered,
		"%d due tiles are ordered by distance to the walker, then the grid (keys %s)"
			% [due.size(), str(keys)],
	)


## The tile whose rect holds `point` (a world point of `district`'s frame).
func _tile_at(district: Node2D, point: Vector2) -> NavigationRegion2D:
	var local := district.to_local(point)
	for tile in _tiles:
		if (tile.get_meta(NavTiles.RECT_META) as Rect2).has_point(local):
			return tile
	return null


## The tile one row below `tile`'s, in its column; null at the grid's bottom.
func _below(tile: NavigationRegion2D) -> NavigationRegion2D:
	if tile == null:
		return null
	var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
	for other in _tiles:
		var other_rect: Rect2 = other.get_meta(NavTiles.RECT_META)
		if (is_equal_approx(other_rect.position.x, rect.position.x)
				and is_equal_approx(other_rect.position.y, rect.end.y)):
			return other
	return null
