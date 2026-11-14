class_name NavTileBurst extends RefCounted
## Navigation domain: one tick's steering tiles of a district, baked one a physics frame and landed
## together (`nav_updater.gd` steps it from its physics process). Each frame that gives a tile its
## polygon pays a synchronisation of the whole steering map (about 0.3 ms in a district), so the
## baking is spread (`NavTiles.prepare`: the polygons held) and the last tile's frame lands them
## all (`NavTiles.land`). The walls the tiles are baked from are parsed once, with the first.

## The tiles still to bake (`NavTiles.due_tiles`), in the order they are.
var tiles: Array[Dictionary] = []
## The bakes made so far, held until the last is made.
var _held: Array[Dictionary] = []
## The walls the burst's tiles are baked from, parsed with the first.
var _walls: Dictionary = {}
## The `GameClock` frame the last tile was baked on, so no frame bakes two.
var _frame := -1


## Start over with `due` (`NavTiles.due_tiles`), read after `land`: the held tiles took their
## polygons, so what is due is what is still due by the tiles as they stand.
func begin(due: Array[Dictionary]) -> void:
	tiles = due


## Whether a tile is still to bake.
func pending() -> bool:
	return not tiles.is_empty()


## The tiles whose polygon is still to be assigned this burst: those still to bake and those baked
## and held. A tile due by the footprints of the moment is in this list or has been landed with
## them (`navigation/tile_burst_lands_before_next_tick`).
func tiles_in_play() -> Array[NavigationRegion2D]:
	var out: Array[NavigationRegion2D] = []
	for entry in tiles + _held:
		out.append(entry["tile"])
	return out


## Bake the first of the tiles still to bake and hold it, on a `GameClock` frame none was baked on
## yet; the last one lands the burst. A single tile lands in the call that bakes it.
func step(region: NavigationRegion2D, site: NavSite) -> void:
	if tiles.is_empty() or GameClock.frame() == _frame:
		return
	_frame = GameClock.frame()
	if _walls.is_empty():
		_walls = NavTiles.parse_for(region, site, tiles)
	var held := NavTiles.prepare(site, tiles.pop_front(), _walls)
	if not held.is_empty():
		_held.append(held)
	if tiles.is_empty():
		land()


## Give the held tiles their polygons, all at once, and end the burst's parse.
func land() -> void:
	NavTiles.land(_held)
	_held.clear()
	_walls = {}


## Drop everything: the match is gone.
func clear() -> void:
	tiles.clear()
	_held.clear()
	_walls = {}
