extends GameTest
## Every border two steering tiles of a district share is welded: where a polygon edge of one tile
## lies along a polygon edge of its neighbour, both are the same edge to the NavigationServer (the
## same two 1 px cells), so the map joins them by its edge hash and needs no edge-connection pass
## (`steering_routes_match_edge_connections`). A tile's baked edge along its border spans a stretch
## where the neighbour's has more vertices (a wall's tip touching the line, a hole ending on it);
## the tiles are split at each other's vertices (`NavSeams`). Welded as built, and again after a
## character stops on a corner where four tiles meet (the updater re-bakes them and lands them
## together).

const Seams := preload("res://tests/_navigation/seam_probe.gd")
const SEED := 7
## How long (s) the updater is given to re-bake and land the tiles a character stopped in.
const LANDS_WITHIN := 1.5
## Which tiles' corners the character stops on, as fractions of the grid.
const STOPS := [0.5, 0.3, 0.7]


func describe() -> Dictionary:
	return {
		"name": "Every border between two steering tiles is welded",
		"description": "Where two neighbouring steering tiles' polygon edges overlap along their "
			+ "shared border, they are one edge to the server: the same two 1 px cells; as built "
			+ "and after a character stops on a corner of four tiles.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(_seed())
	s.actor(&"p", &"puppet", Vector2.ZERO)


## The district's seed.
func _seed() -> int:
	return SEED


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region := t.world.find_children("NavRegion", "NavigationRegion2D", true, false)[0]
	var tiles := NavBuilder.steering_regions(region as NavigationRegion2D)
	if not t.require(Seams.pairs(tiles).size() > 20, "premise: the steering map is tiles"):
		return
	_expect_welded(t, tiles, "as built")
	for fraction: float in STOPS:
		var tile: NavigationRegion2D = tiles[int(tiles.size() * fraction)]
		var rect: Rect2 = tile.get_meta(NavTiles.RECT_META)
		var baked := NavTiles.baked_total
		t.actor(&"p").global_position = tile.to_global(rect.end)
		await t.seconds(LANDS_WITHIN)
		t.check(NavTiles.baked_total > baked, "premise: the character's stop re-baked tiles")
		_expect_welded(t, tiles, "after a character stopped at %s" % tile.to_global(rect.end))


## The borders of `tiles` are welded (`what` names the moment).
func _expect_welded(t: TestContext, tiles: Array, what: String) -> void:
	var faults := Seams.unwelded(tiles)
	t.check(
		faults.is_empty(),
		"every shared border is welded %s; not: %s" % [what, faults.slice(0, 6)],
	)
	t.expect_eq(NavSeams.unsplit_total, 0, "no edge of a real bake was left uncut %s" % what)
