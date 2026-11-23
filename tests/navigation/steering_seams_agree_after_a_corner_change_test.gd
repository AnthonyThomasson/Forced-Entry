extends GameTest
## A change in one tile of a 3x3 block of real baked steering tiles leaves every border agreed
## (`NavSeams.weld`, review of #194 nav3d-a): a hole that lands on a corner of the centre tile
## alone (only its holes change, it alone is baked) can close a border cell there, which opens a
## stretch on the border of a tile across the corner that neither the centre nor its edge
## neighbours' own re-bake sees. After the weld every pair of neighbouring tiles holds the same
## walkable stretches on its shared border, every edge on it is one edge to the server, and the
## weld did not end with a tile still to agree (`rounds_exhausted_total`, `unsplit_total`).

const Seams := preload("res://tests/_navigation/seam_probe.gd")
const SEED := 7
## Half the side (px) of the square hole placed at a corner of the centre tile.
const HOLE_HALF := 6.0
## Where (px) from the corner the hole's centre is placed, in each axis.
const SHIFTS := [
	Vector2(0, 0),
	Vector2(-10, -10),
	Vector2(10, 10),
	Vector2(-10, 10),
	Vector2(10, -10),
]
## How near (px) two stretches' ends are to be the same.
const SAME := 0.01

var _region: NavigationRegion2D
var _site: NavSite
var _tiles: Array


func describe() -> Dictionary:
	return {
		"name": "A corner hole in the centre of 3x3 steering tiles leaves every border agreed",
		"description": "Only the centre tile's holes change (a square on each of its corners, "
			+ "and taken away again): after the weld the walkable stretches of every shared "
			+ "border are the same on both sides, every border is welded, and no weld ran out "
			+ "of rounds.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	_region = t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	_site = NavBuilder.site_of(_region, district, WorldGen.district_rooms(district))
	_tiles = NavBuilder.steering_regions(_region)
	var centre := _centre_of_a_block()
	if not t.require(centre != null, "premise: the district has a 3x3 block of whole tiles"):
		return
	var rect: Rect2 = centre.get_meta(NavTiles.RECT_META)
	var block := _block(centre)
	t.expect_eq(block.size(), 9, "the block is nine tiles")
	_expect_agreed(t, block, "as built")
	var original: Array = centre.get_meta(NavTiles.HOLES_META)
	var baked := NavTiles.baked_total
	for corner: Vector2 in [
			rect.position, Vector2(rect.end.x, rect.position.y),
			Vector2(rect.position.x, rect.end.y), rect.end]:
		for shift: Vector2 in SHIFTS:
			var at := centre.to_global(corner) + shift
			_bake_centre(centre, original + [_square(at)])
			_expect_agreed(t, block, "with a hole at %s" % at)
			_bake_centre(centre, original)
			_expect_agreed(t, block, "after the hole at %s was taken away" % at)
	t.check(NavTiles.baked_total > baked, "premise: the centre tile was baked for each hole")


## A tile of the grid whose eight neighbours (rects a tile's size away) are all tiles, else null.
func _centre_of_a_block() -> NavigationRegion2D:
	for tile: NavigationRegion2D in _tiles:
		if _block(tile).size() == 9:
			return tile
	return null


## `centre` and the tiles of the grid round it that are whole tiles.
func _block(centre: NavigationRegion2D) -> Array:
	var rect: Rect2 = centre.get_meta(NavTiles.RECT_META)
	var out: Array = []
	for tile: NavigationRegion2D in _tiles:
		var other: Rect2 = tile.get_meta(NavTiles.RECT_META)
		var apart := (other.position - rect.position).abs()
		if apart.x <= NavTiles.SIZE and apart.y <= NavTiles.SIZE and other.size == rect.size:
			out.append(tile)
	return out


## A square hole (world outline) about `at`.
func _square(at: Vector2) -> PackedVector2Array:
	var h := Vector2.ONE * HOLE_HALF
	return PackedVector2Array([
		at - h, at + Vector2(h.x, -h.y), at + h, at + Vector2(-h.x, h.y),
	])


## Bake `tile` alone from `holes` on a worker thread and land it (it and its neighbours welded).
func _bake_centre(tile: NavigationRegion2D, holes: Array) -> void:
	var entry := { "tile": tile, "holes": holes }
	var held := NavTiles.prepare(_site, entry, NavTiles.parse_for(_region, _site, [entry]))
	if held != null:
		NavTiles.land([held])


## Every pair of neighbours in `block` holds the same walkable stretches on its shared border, the
## borders are welded and the weld left nothing to agree (`what` names the moment).
func _expect_agreed(t: TestContext, block: Array, what: String) -> void:
	var apart := _disagreeing(block)
	t.check(
		apart.is_empty(),
		"every border holds the same stretches %s; not: %s" % [what, apart.slice(0, 3)],
	)
	var faults := Seams.unwelded(block)
	t.check(faults.is_empty(), "every border is welded %s; not: %s" % [what, faults.slice(0, 4)])
	t.expect_eq(NavSeams.unsplit_total, 0, "no edge was left uncut %s" % what)
	t.expect_eq(NavSeams.rounds_exhausted_total, 0, "no weld ran out of rounds %s" % what)


## A line for each border of `block` whose two sides hold other walkable stretches over the part
## the two tiles share.
func _disagreeing(block: Array) -> Array[String]:
	var out: Array[String] = []
	for tile: NavigationRegion2D in block:
		for entry: Dictionary in NavSeams.neighbours(tile):
			var other: NavigationRegion2D = entry["tile"]
			if not block.has(other):
				continue
			var side: int = entry["side"]
			var span := _shared(tile, other, side)
			var mine := _clip((tile.get_meta(NavSeams.NOW_META) as Array)[side], span)
			var theirs := _clip((other.get_meta(NavSeams.NOW_META) as Array)[side ^ 1], span)
			if not _same(mine, theirs):
				out.append(
					"%s side %d: %s against %s: %s" % [tile.name, side, mine, other.name, theirs])
	return out


## The stretch along the border of `tile`'s side `side` that `tile` and `other` share.
func _shared(tile: NavigationRegion2D, other: NavigationRegion2D, side: int) -> Vector2:
	var a: Rect2 = tile.get_meta(NavTiles.RECT_META)
	var b: Rect2 = other.get_meta(NavTiles.RECT_META)
	if side < NavSeams.TOP:
		return Vector2(maxf(a.position.y, b.position.y), minf(a.end.y, b.end.y))
	return Vector2(maxf(a.position.x, b.position.x), minf(a.end.x, b.end.x))


## The `stretches` cut to `span`, those left sorted.
func _clip(stretches: Array, span: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for stretch: Vector2 in stretches:
		var within := Vector2(maxf(stretch.x, span.x), minf(stretch.y, span.y))
		if within.y - within.x > SAME:
			out.append(within)
	return out


## Whether two sorted lists of stretches are the same.
func _same(a: Array[Vector2], b: Array[Vector2]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true
