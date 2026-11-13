extends GameTest
## A district's steering map answers the same routes with its edge-connection pass off as on, so it
## leaves the pass off (it costs ~10 ms every time a tile's polygon changes; the tiles are
## welded: `steering_seams_welded`). Asked every ordered pair of the tiles' probe points and both
## ways across every seam edge, the map answers with the pass off and then on, and the paths are
## the same points, as built and after a character stops on a corner of four tiles (the updater
## re-bakes and lands them). That holds on these seeds and on a lone house; on others
## (`_other_routes_test`) a route in a hundred differs, the pass off never the longer
## (`steering-edge-connections.md`). The steering map is built without the pass.

const Seams := preload("res://tests/_navigation/seam_probe.gd")
const SEED := 7
## How far (px) a point of a path may lie from the same point of the other. The tiles' seams are
## the same edges, so the paths are the same.
const SAME := 0.01
## How long (s) the updater is given to re-bake and land the tiles a character stopped in.
const LANDS_WITHIN := 1.5
## Which tiles' corners the character stops on, as fractions of the grid.
const STOPS := [0.5, 0.3]


func describe() -> Dictionary:
	return {
		"name": "The steering map routes the same with its edge connections off as on",
		"description": "Every route between the tiles' probe points and across every seam is "
			+ "the same path with the pass turned on, as built and after a re-bake.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	_world(s)
	s.actor(&"p", &"puppet", Vector2.ZERO)


## The world: a district of `_seed()`.
func _world(s: TestSetup) -> void:
	s.district(_seed())


## The district's seed.
func _seed() -> int:
	return SEED


## Whether the character stops on tile corners (a lone house has none).
func _stops() -> Array:
	return STOPS


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var tiles := NavBuilder.steering_regions(region as NavigationRegion2D)
	var map := NavBuilder.steering_map(t.world.get_world_2d().navigation_map)
	if not t.require(not tiles.is_empty() and map.is_valid(), "premise: a steering map"):
		return
	t.check(
		not NavigationServer2D.map_get_use_edge_connections(map),
		"the steering map is built without its edge-connection pass",
	)
	_expect_same(t, map, tiles, "as built")
	for fraction: float in _stops():
		var tile: NavigationRegion2D = tiles[int(tiles.size() * fraction)]
		var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
		var baked := NavTiles.baked_total
		t.actor(&"p").global_position = tile.to_global(rect.end)
		await t.seconds(LANDS_WITHIN)
		t.check(NavTiles.baked_total > baked, "premise: the character's stop re-baked tiles")
		_expect_same(t, map, tiles, "after a character stopped at %s" % tile.to_global(rect.end))


## `map` answers the same routes between `tiles`' points with the pass off as on.
func _expect_same(t: TestContext, map: RID, tiles: Array, what: String) -> void:
	var points := Seams.points(tiles, _stride())
	var crossings := Seams.crossings(tiles)
	_set_edge_connections(map, false)
	var off := Seams.all_pairs(map, points)
	var off_cross := Seams.both_ways(map, crossings)
	_set_edge_connections(map, true)
	var on := Seams.all_pairs(map, points)
	var on_cross := Seams.both_ways(map, crossings)
	_set_edge_connections(map, false)
	_check(t, Seams.compare(on, off), "%d routes %s" % [on.size(), what])
	_check(t, Seams.compare(on_cross, off_cross), "%d seam crossings %s" % [on_cross.size(), what])


## Every how-manyth polygon of a lone house's region is a point.
func _stride() -> int:
	return 1


## `map` with its edge-connection pass `on` or off, synchronised now.
func _set_edge_connections(map: RID, on: bool) -> void:
	NavigationServer2D.map_set_use_edge_connections(map, on)
	NavigationServer2D.map_force_update(map)


## The most (px) a route may be shorter with the pass off than on; negative: no route differs
## (over `SAME`), the seeds where the pass joins nothing the welded tiles do not.
func _gain_bound() -> float:
	return -1.0


## The most routes that may be longer with the pass off than on, and by how much (px): the pass
## links two tiles through the point where four meet, between two obstacle corners that only touch,
## which no shared edge does, and a route through it is shorter than the one round.
func _longer_bound() -> Vector2:
	return Vector2.ZERO


## `difference` (`Seams.compare`) is what the seed allows: no route that differs by over `SAME`
## (`_gain_bound` negative), else at most `_longer_bound` routes longer with the pass off, none that
## only the pass finds a way to, and none shorter by over the bound.
func _check(t: TestContext, difference: Dictionary, what: String) -> void:
	var message := (
		(
			"%s with the pass off as on; %d differ, the worst by %.2f px, %d longer (by up to "
			+ "%.2f px), %d shorter (by up to %.2f px), %d reached by one only"
		)
		% [
			what, difference["pairs"], difference["worst"], difference["longer"],
			difference["detour"], difference["shorter"], difference["gain"], difference["reach"],
		]
	)
	if _gain_bound() < 0.0:
		t.check(difference["pairs"] == 0 or difference["worst"] <= SAME, message)
		return
	t.check(
		difference["longer"] <= _longer_bound().x
		and difference["detour"] <= _longer_bound().y
		and difference["reach"] == 0
		and difference["gain"] <= _gain_bound(),
		message,
	)
