extends GameTest
## The steering map of a district is a grid of tiles, and a re-bake after a character stops only
## re-bakes the tiles it reaches (#182). The whole footprint in one region is a bake of every wall
## and piece of furniture of the district on the main thread each time a character stops; each tile
## is baked from what reaches it and again only when that changed. A tile re-baked is one whose
## `navigation_polygon` was replaced (a new resource), read off every tile before and after
## `NavBuilder.rebake_steering`.

const SEED := 7
## A character stands this far (px) in from the corner of the streets' rect.
const CORNER_IN := 100.0
## The most tiles a character's hole can reach (a seam of four) and the most one move touches (the
## spot it left and the one it reached).
const MOST_REACHED := 4
const MOST_MOVED := 8

var _district: Node2D
var _region: NavigationRegion2D
var _rooms: Array
var _tiles: Array


func describe() -> Dictionary:
	return {
		"name": "A character stopping re-bakes only the steering tiles it touches",
		"description": "In a district the steering map is many regions; a character stopping "
			+ "in the street re-bakes the one to four tiles round it, nothing re-bakes when "
			+ "nothing changed, and a character crossing the district re-bakes the tiles it left "
			+ "and reached, not the map.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
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
	if not t.require(_tiles.size() > 2 * MOST_MOVED, "premise: the steering map is many tiles"):
		return
	var streets := WorldGen.district_bounds(_district)
	var front := streets.position + Vector2(CORNER_IN, CORNER_IN)
	var puppet := t.actor(&"p")

	puppet.global_position = front
	await t.frames(3)
	_rebaked()  # takes the character in
	puppet.global_position = front + Vector2(300, 0)
	await t.frames(3)
	var stopped := _rebaked()
	t.check(
		stopped >= 1 and stopped <= MOST_REACHED,
		"a character stopping 300 px along re-bakes 1 to %d tiles, not %d of %d"
			% [MOST_REACHED, stopped, _tiles.size()],
	)
	t.expect_eq(_rebaked(), 0, "a re-bake with nothing changed re-bakes no tile")
	puppet.global_position = streets.end - Vector2(CORNER_IN, CORNER_IN)
	await t.frames(3)
	var crossed := _rebaked()
	t.check(
		crossed >= 2 and crossed <= MOST_MOVED,
		"a character crossing the district re-bakes the tiles it left and reached (%d of %d)"
			% [crossed, _tiles.size()],
	)


## How many of the steering tiles have a polygon other than before `NavBuilder.rebake_steering`
## (a re-bake replaces it).
func _rebaked() -> int:
	var before: Array = _tiles.map(
		func(tile: NavigationRegion2D) -> NavigationPolygon: return tile.navigation_polygon,
	)
	NavBuilder.rebake_steering(_region, _district, _rooms)
	var changed := 0
	for i in _tiles.size():
		if (_tiles[i] as NavigationRegion2D).navigation_polygon != before[i]:
			changed += 1
	return changed
