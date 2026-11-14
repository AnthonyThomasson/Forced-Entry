extends GameTest
## A tick that finds a steering burst still open lands what the burst holds before it reads which
## tiles are due (#195). The tiles' own baked holes are what "due" compares the footprints with, and
## a held polygon is not on its tile yet: a tick that read them first could bake a held tile again
## or, when the footprints had gone back to what the tile had landed with, call it up to date and
## then land the stale polygon over it.
## The updater's interval is a few frames here, so ticks come while a burst of several tiles is
## still baking. A puppet that made a tile due then goes back to where it stood while that tile's
## polygon is held: the next tick must leave no tile due by the footprints of that moment that is
## neither still to bake nor held (`NavUpdater.tiles_in_play`).

const SEED := 7
const CORNER_IN := 100.0
## Puppets stand this far (px) apart along their row, and move this far.
const STEP := 700.0
const MOVE := 300.0
## The updater's interval (s): three physics frames.
const INTERVAL := 0.05
const WAIT_FRAMES := 60

var _tiles: Array[NavigationRegion2D] = []


func describe() -> Dictionary:
	return {
		"name": "A tick lands the burst's held tiles before it reads which are due",
		"description": "With ticks a few frames apart a burst is still open at the next one; a "
			+ "puppet goes back to where it stood while its tile's polygon is held, and after "
			+ "that tick every tile due by the footprints is still to bake or held.",
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
	var updater := t.world.get_node("NavUpdater")
	_tiles = NavBuilder.steering_regions(region as NavigationRegion2D)
	var front := WorldGen.district_bounds(district).position + Vector2(CORNER_IN, CORNER_IN)
	var stopped: Array[Node2D] = [t.actor(&"a"), t.actor(&"b"), t.actor(&"c")]
	for i in stopped.size():
		stopped[i].global_position = front + Vector2(STEP * i, 0)
	# The walker stands in the tile below the first puppet's: baked first, the first puppet's
	# tile next (the nearest to it).
	var below := _below(_tile_at(district, stopped[0].global_position))
	if not t.require(below != null, "premise: the row of tiles has one below it"):
		return
	t.actor(&"w").global_position = district.to_global(
		(below.get_meta(NavTiles.RECT_META) as Rect2).get_center())
	await t.seconds(2.0)  # the ticks that take them in
	(updater.get_node("RebakeTimer") as Timer).wait_time = INTERVAL
	var home := stopped[0].global_position
	var baked := NavTiles.baked_total
	for puppet in stopped:
		puppet.global_position += Vector2(MOVE, 0)
	t.puppet(&"w").walk(Vector2.RIGHT)
	var held := false
	for _i in WAIT_FRAMES:
		await t.frames(1)
		if NavTiles.baked_total - baked >= 2:
			held = true
			break
	if not t.require(held, "premise: a burst of at least two tiles is open"):
		return
	stopped[0].global_position = home  # back to what its tile landed with
	var probe := TickProbe.new()
	probe.watch(updater, district, region as NavigationRegion2D)
	await t.until(func() -> bool: return probe.ticks >= 1, 1.0)
	t.check(probe.ticks >= 1, "a tick came while the burst was open")
	t.check(
		probe.stranded.is_empty(),
		"after the tick every tile due by the footprints is still to bake or held (stranded: %s)"
			% str(probe.stranded),
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


## Counts the updater's ticks from now on and, at the first, reads which tiles are due by the
## footprints of that moment but are neither to bake nor held. Connected after the updater's own
## handler, so it runs after the part of the tick that does not wait a frame.
class TickProbe extends RefCounted:
	var ticks := 0
	var stranded: Array[String] = []
	var _updater: Node
	var _district: Node2D
	var _region: NavigationRegion2D

	func watch(updater: Node, district: Node2D, region: NavigationRegion2D) -> void:
		_updater = updater
		_district = district
		_region = region
		(updater.get_node("RebakeTimer") as Timer).timeout.connect(_on_tick)

	func _on_tick() -> void:
		ticks += 1
		if ticks > 1:
			return
		var site := NavBuilder.site_of(_region, _district, WorldGen.district_rooms(_district))
		var in_play: Array[NavigationRegion2D] = _updater.tiles_in_play()
		var due := NavTiles.due_tiles(
			_region, site, NavBuilder.furniture_holes(_district),
			NavBuilder.character_holes(_district.get_parent()),
		)
		for entry: Dictionary in due:
			if not in_play.has(entry["tile"]):
				stranded.append(String(entry["tile"].name))
