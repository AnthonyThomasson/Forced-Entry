extends GameTest
## A district's steering tiles are baked from the walls of the towers that reach them, parsed tower
## by tower and kept (#182), where the whole district parsed at once costs ~7 ms of a frame. This
## checks the walls handed to a tile are the walls a parse of the whole district finds there: every
## obstruction outline of the whole parse that reaches the area is among them, as the district
## stands and again after a wall is shot up (its collider rebuilt), so a tile never bakes from a
## wall that is gone or misses one that is new.

const SEED := 7
const RADIUS := 14.0
## How far (px) round a point the area a tile reaches is.
const AREA := 300.0
## A tower far from the house, whose area is checked too: this many px along the district.
const FAR_IN := 150.0


func describe() -> Dictionary:
	return {
		"name": "Steering tiles bake from the same walls a whole parse finds",
		"description": "The walls the tower-by-tower parse hands the steering tiles include every "
			+ "wall of a whole-district parse in the same area, before and after a wall is dented.",
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
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var site := NavSite.new(district, WorldGen.district_rooms(district), RADIUS)
	var streets := WorldGen.district_bounds(district)
	var areas: Array[Rect2] = [
		Rect2(house.position, Vector2.ZERO).grow(AREA),
		Rect2(streets.end - Vector2(FAR_IN, FAR_IN), Vector2.ZERO).grow(AREA),
	]
	for area in areas:
		_compare(t, region, site, area, "as the district stands, near %s" % str(area.get_center()))
	_compare_planning(t, region, site)
	var wall := _wall_of(house)
	if not t.require(wall != null, "the house has a wall"):
		return
	_dent(wall)
	await t.frames(3)  # the wall's collider is rebuilt from the dents
	var around := Rect2(wall.global_position, Vector2.ZERO).grow(AREA)
	_compare(t, region, site, around, "after a wall of the house is shot up")


## The walls a planning re-bake is made from, with no furniture moved, are every wall of the whole
## parse.
func _compare_planning(t: TestContext, region: NavigationRegion2D, site: NavSite) -> void:
	var furniture := NavBuilder.furniture_holes(site.house)
	var planning: Array = NavTiles.walls_after(region, site, furniture, furniture)["obstruction"]
	var whole: Array = NavSource.walls_of(site.house, RADIUS)["obstruction"]
	var missing := 0
	for wall: PackedVector2Array in whole:
		if not planning.has(wall):
			missing += 1
	t.expect_eq(missing, 0, "the planning walls hold every wall of the whole parse")


## A wall of `house` (a body that reports its segments).
func _wall_of(house: Node2D) -> Node2D:
	for node in house.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			return node
	return null


## Shoot `wall`'s first segment four times.
func _dent(wall: Node2D) -> void:
	var seg: PackedVector2Array = wall.wall_segments()[0]
	for k in 4:
		var hit := HitInfo.new()
		hit.position = wall.to_global(seg[0].lerp(seg[1], 0.2 + 0.15 * k))
		hit.normal = (seg[1] - seg[0]).normalized().orthogonal()
		hit.direction = -hit.normal
		hit.damage = 40.0
		hit.speed_factor = 1.0
		wall.take_hit(hit)


## Every outline of the whole parse that reaches `area` is among the tile walls for `area`.
func _compare(
	t: TestContext,
	region: NavigationRegion2D,
	site: NavSite,
	area: Rect2,
	when: String,
) -> void:
	var tiled: Array = NavTiles.walls_reaching(region, site, [area])
	var whole: Array = NavSource.walls_of(site.house, RADIUS)["obstruction"]
	var want := 0
	var missing := 0
	for outline: PackedVector2Array in whole:
		if area.intersects(NavSource.outline_bounds(outline)):
			want += 1
			if not tiled.has(outline):
				missing += 1
	if not t.require(want > 0, "premise: walls reach the area (%s)" % when):
		return
	t.expect_eq(missing, 0, "every wall of the whole parse is among the tile walls (%s)" % when)
