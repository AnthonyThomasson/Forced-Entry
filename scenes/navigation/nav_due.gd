class_name NavDue extends RefCounted
## Navigation domain: `NavTiles.due_tiles` made in steps, so a tick of the updater (`NavTick`) pays
## a slice of it a physics frame. The footprints are binned by the tiles' reaches a chunk of
## outlines at a time (a chunk binned alone appends to each tile's list in the order the whole
## would, so the bins are the same), then the tiles are checked and keyed a few at a time, and the
## due ones sorted. `NavTiles.due_tiles` runs the steps to the end in one call, so there is one
## rule.

## The tiles of the steering map, their reaches and the outlines to bin (the furniture's, then the
## characters'), with how far the binning and the tile check have got.
var _region: NavigationRegion3D
var _site: NavSite
var _walkers: Array[Vector2]
var _tiles: Array = []
var _reaches: Array[Rect2] = []
var _outlines: Array = []
var _bins: Array = []
var _binned := 0
var _checked := 0
var _keyed: Array[Dictionary] = []


## The due tiles of `region` (`NavTiles.due_tiles`' arguments).
func _init(
	region: NavigationRegion3D,
	site: NavSite,
	furniture: Array,
	characters: Array,
	walkers: Array[Vector2],
) -> void:
	_region = region
	_site = site
	_walkers = walkers
	_tiles = NavBuilder.steering_regions(region)
	_reaches = NavTiles.reaches_of(_tiles)
	_outlines = furniture + characters
	for _tile in _tiles:
		_bins.append([])


## Do one step: bin up to `outlines` outlines, or, once they are binned, check up to `tiles` tiles.
## True once the due tiles are made (`result`).
func step(outlines: int, tiles: int) -> bool:
	if _binned < _outlines.size():
		var chunk := _outlines.slice(_binned, _binned + outlines)
		_binned += chunk.size()
		var binned := NavTiles.bin(chunk, _reaches, _site.house.position)
		for i in _bins.size():
			(_bins[i] as Array).append_array(binned[i])
		return false
	var stop := mini(_checked + tiles, _tiles.size())
	while _checked < stop:
		var i := _checked
		_checked += 1
		if NavTiles.holes_unchanged(_tiles[i], _bins[i]):
			continue
		var rect: Rect2 = _tiles[i].get_meta(NavTiles.RECT_META)
		var gap := NavTiles.gap_of(rect, _walkers, _site)
		_keyed.append({ "tile": _tiles[i], "holes": _bins[i], "gap": gap, "i": i })
	if _checked < _tiles.size():
		return false
	_keyed.sort_custom(NavTiles.nearer)
	return true


## The tiles due, in the order they are baked (`NavTiles.due_tiles`), once `step` has returned true.
func result() -> Array[Dictionary]:
	return _keyed
