class_name NavTileBurst extends RefCounted
## Navigation domain: one tick's steering tiles of a district, started baking a physics frame each
## (on a worker thread) and landed together (`nav_updater.gd` steps it from its physics process).
## A frame that gives a tile its polygon pays a synchronisation of the whole steering map (about
## 0.3 ms in a district), so the starting is spread (`NavTiles.prepare`: the source gathered, the
## bake held) and the burst lands all its tiles in one frame, `NavBakeConfig.tile_frames` after
## the last was started (`NavTiles.land`). The walls the tiles are baked from are parsed once,
## with the first.

## How many frames past its due one a burst waits for a free landing frame (`NavBake.landing_taken`)
## before it lands whatever: bakes landing back to back cannot hold its tiles off forever.
const MOST_SLIP := 3

## The tiles still to bake (`NavTiles.due_tiles`), in the order they are.
var tiles: Array[Dictionary] = []
## The bakes made so far, held until the last is made.
var _held: Array[NavTileBake] = []
## The walls the burst's tiles are baked from, parsed with the first.
var _walls: Dictionary = {}
## The `GameClock` frame the last tile was started on, so no frame starts two.
var _frame := -1
## The `GameClock` frame the held tiles land on (`NavBakeConfig.tile_frames` after the last tile
## was started); -1 while tiles are still to start.
var _land_at := -1


## Start over with `due` (`NavTiles.due_tiles`), read after `land`: the held tiles took their
## polygons, so what is due is what is still due by the tiles as they stand.
func begin(due: Array[Dictionary]) -> void:
	tiles = due


## Whether a tile is still to bake, or baked and waiting for its landing frame.
func pending() -> bool:
	return not tiles.is_empty() or not _held.is_empty()


## The tiles whose polygon is still to be assigned this burst: those still to bake and those baked
## and held. A tile due by the footprints of the moment is in this list or has been landed with
## them (`navigation/tile_burst_lands_before_next_tick`).
func tiles_in_play() -> Array[NavigationRegion3D]:
	var out: Array[NavigationRegion3D] = []
	for entry in tiles:
		out.append(entry["tile"])
	for held in _held:
		out.append(held.tile)
	return out


## Start the first of the tiles still to bake (on a worker thread) and hold it, on a `GameClock`
## frame none was started on yet; the frame `NavBakeConfig.tile_frames` after the last one was
## started lands the burst, on a frame no bake landed on (`NavBake.landing_taken`: one landing a
## frame, the bake's first, as its signal runs before the updater's step; a burst that finds it
## taken lands on the next frame, up to `MOST_SLIP` frames, then whatever). Nothing to land (every
## tile was up to date): the burst ends at once.
func step(region: NavigationRegion3D, site: NavSite) -> void:
	if GameClock.frame() == _frame:
		return
	_frame = GameClock.frame()
	if not tiles.is_empty():
		if _walls.is_empty():
			_walls = NavTiles.parse_for(region, site, tiles)
		var held := NavTiles.prepare(site, tiles.pop_front(), _walls)
		if held != null:
			_held.append(held)
		if tiles.is_empty():
			_land_at = _frame + NavBakeConfig.tile_frames
	if tiles.is_empty() and _held.is_empty():
		land()
	elif tiles.is_empty() and _held_may_land():
		land()


## Give the held tiles their polygons, all at once, and end the burst's parse. A landing takes its
## `GameClock` frame (`NavBake.take_landing`), a forced one too: a bake due on it lands the next.
func land() -> void:
	if not _held.is_empty():
		NavBake.take_landing()
	NavTiles.land(_held)
	_held.clear()
	_walls = {}
	_land_at = -1


## Whether the held tiles' frame has come and no landing has taken it, or they have waited
## `MOST_SLIP` frames for one.
func _held_may_land() -> bool:
	return _frame >= _land_at and (not NavBake.landing_taken() or _frame >= _land_at + MOST_SLIP)


## Drop everything: the match is gone.
func clear() -> void:
	NavTiles.abandon(_held)
	tiles.clear()
	_held.clear()
	_walls = {}
	_land_at = -1
