extends GameTest
## A district's steering tiles are baked from the walls of the towers that reach them, parsed tower
## by tower (`NavTiles._refreshed`). A tower is a child of the house; a wall that is a child of the
## house itself is no tower's, and a parse of a tower finds only what is under it, so the walls are
## then parsed whole. This puts a wall straight under the house (a wall is a plan handle with no
## engine body, so only its group says what it is) and checks the walls handed to a tile still hold
## every outline of the whole parse that reaches the area, the moved wall's among them.

const SEED := 7
const RADIUS := 14.0
const AREA := 300.0


func describe() -> Dictionary:
	return {
		"name": "A wall straight under the district is baked into a tile",
		"description": "With a wall moved to be a child of the house itself, the tower-by-tower "
			+ "parse falls back to the whole parse and the tile walls hold the moved wall.",
		"tags": ["navigation", "district", "walls"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	var house := t.world.get("house") as Node2D
	var region: NavigationRegion3D = t.world.find_children(
		"NavRegion", "NavigationRegion3D", true, false,
	)[0]
	var site := NavSite.new(district, WorldGen.district_rooms(district), RADIUS)
	var wall: Node2D = null
	for node in NavTwins.walls_under(house):
		if node.get_parent() != site.house:
			wall = node
			break
	if not t.require(wall != null, "premise: the house has a wall below its towers"):
		return
	wall.reparent(site.house, true)
	await t.frames(3)
	t.require(wall.get_parent() == site.house, "premise: the wall is a child of the house")
	var area := Rect2(wall.global_position, Vector2.ZERO).grow(AREA)
	var tiled: Array = NavTiles.walls_reaching(region, site, [area])
	var whole: Array = NavSource.walls_of(site.house)["obstruction"]
	var want := 0
	var missing := 0
	for outline: PackedVector2Array in whole:
		if area.intersects(NavSource.outline_bounds(outline)):
			want += 1
			if not tiled.has(outline):
				missing += 1
	t.require(want > 0, "premise: walls reach the area")
	t.expect_eq(missing, 0, "every wall of the whole parse is among the tile walls")
