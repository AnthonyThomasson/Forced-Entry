extends GameTest
## Steering tiles take only the outlines whose bounds reach them. Binning those bounds by grid range
## must give the same lists, in the same outline order, as trying every outline against every tile:
## the border around a tile still counts, and a character's old tiles are vacated when it moves.
## Static outlines have their bounds measured once, not again on every re-bake (#192 AC13).

const SEED := 7


func describe() -> Dictionary:
	return {
		"name": "Grid-range steering bins match the full tile scan",
		"description": "On a district, grid-range bins equal the all-tiles scan including border "
			+ "reach and a moved character's vacated tiles, with fewer candidate checks; unchanged "
			+ "outlines reuse their bounds and a moved outline is measured again.",
		"tags": ["navigation", "district", "steering"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", false)
	# The bounds cache is keyed by an outline's value and outlives a test: an earlier run in the
	# process that measured the moved puppet's outline would leave nothing to measure again here.
	s.set_static(NavTiles, &"_bounds", {})
	s.actor(&"p", &"puppet", Vector2.ZERO)


func run(t: TestContext) -> void:
	var counters := NavTiles as GDScript
	if not t.require(
		counters.get("intersection_tests") != null,
		"the grid-range bin exposes its candidate intersection checks",
	):
		return
	var fixture := await _district(t)
	await _bins_match(t, counters, fixture)
	await _bounds_reused(t, counters, fixture)
	_large_reach(t)
	_grid_extremes(t)


## The real district, its steering tiles and one character that can vacate their bins.
func _district(t: TestContext) -> Dictionary:
	await t.seconds(0.5)
	var district := t.world.get("district") as Node2D
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var tiles := NavBuilder.steering_regions(region)
	return {
		"district": district, "tiles": tiles, "reaches": _reaches(tiles),
		"furniture": NavBuilder.furniture_holes(district),
		"streets": WorldGen.district_bounds(district), "puppet": t.actor(&"p"),
	}


## Compare the district's bins after a character crosses it, old tiles included.
func _bins_match(t: TestContext, counters: GDScript, fixture: Dictionary) -> void:
	var streets := fixture["streets"] as Rect2
	var puppet := fixture["puppet"] as Node2D
	var district := fixture["district"] as Node2D
	puppet.global_position = streets.position + Vector2(100, 100)
	await t.frames(3)
	var old_character: PackedVector2Array = NavBuilder.character_holes(district.get_parent())[0]
	var old_reached := _containing(
		_full_scan([old_character], fixture["reaches"], district.position), old_character,
	)

	puppet.global_position = streets.end - Vector2(100, 100)
	await t.frames(3)
	var outlines: Array = fixture["furniture"] + NavBuilder.character_holes(district.get_parent())
	var before := int(counters.get("intersection_tests"))
	var fast := NavTiles.bin(outlines, fixture["reaches"], district.position)
	var candidates := int(counters.get("intersection_tests")) - before
	var plain := _full_scan(outlines, fixture["reaches"], district.position)
	t.expect_eq(fast, plain, "every tile holds exactly the full scan's outlines, in their order")
	t.check(
		candidates < outlines.size() * fixture["reaches"].size(),
		"grid ranges avoid all-tiles checks (%d of %d)" % [
			candidates,
			outlines.size() * fixture["reaches"].size(),
		],
	)
	_border_reached(t, fixture, outlines, plain)
	_vacated(t, fast, old_reached, _containing(fast, outlines[-1]), outlines[-1])


func _vacated(
	t: TestContext, bins: Array, old: Array[int], new: Array[int], character: PackedVector2Array,
) -> void:
	t.check(old != new, "premise: the character reaches a different set of tiles")
	for i in old:
		t.check(not bins[i].has(character), "a vacated tile no longer holds the moved character")
	for i in new:
		t.check(bins[i].has(character), "the reached tile holds the moved character")


## A second identical bin measures no bounds; moving only the character measures exactly one.
func _bounds_reused(t: TestContext, counters: GDScript, fixture: Dictionary) -> void:
	var district := fixture["district"] as Node2D
	var reaches := _reaches(fixture["tiles"])
	var outlines: Array = fixture["furniture"] + NavBuilder.character_holes(district.get_parent())
	var before := int(counters.get("bounds_measures"))
	NavTiles.bin(outlines, reaches, district.position)
	t.expect_eq(
		int(counters.get("bounds_measures")) - before, 0, "unchanged outlines reuse their bounds",
	)
	var streets := fixture["streets"] as Rect2
	(fixture["puppet"] as Node2D).global_position = streets.position + Vector2(300, 140)
	await t.frames(3)
	outlines = fixture["furniture"] + NavBuilder.character_holes(district.get_parent())
	before = int(counters.get("bounds_measures"))
	t.expect_eq(
		NavTiles.bin(outlines, reaches, district.position),
		_full_scan(outlines, reaches, district.position),
		"the bins still match after the character moves again",
	)
	t.expect_eq(
		int(counters.get("bounds_measures")) - before, 1,
		"only the moved character's bounds are measured again",
	)


## The planning ring bins against one footprint, not a steering-tile grid; its far outlines count.
func _large_reach(t: TestContext) -> void:
	var reaches: Array[Rect2] = [Rect2(-40, -40, 1000, 800)]
	var near := PackedVector2Array([
		Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20),
	])
	var far := PackedVector2Array([
		Vector2(700, 600), Vector2(720, 600), Vector2(720, 620), Vector2(700, 620),
	])
	var outlines: Array = [near, far]
	t.expect_eq(
		NavTiles.bin(outlines, reaches, Vector2.ZERO),
		_full_scan(outlines, reaches, Vector2.ZERO),
		"one large planning-ring reach keeps its near and far outlines",
	)


## A small grid whose origin is negative: an outline spanning far beyond it, one straddling a tile
## border and one on the negative side still bin as the full scan does, without walking every cell
## the huge box spans.
func _grid_extremes(t: TestContext) -> void:
	var reaches: Array[Rect2] = []
	for y in 2:
		for x in 3:
			var tile := Rect2(
				Vector2(x, y) * NavTiles.SIZE - Vector2(600, 400),
				Vector2.ONE * NavTiles.SIZE,
			)
			reaches.append(tile.grow(NavTiles.BORDER))
	var huge := PackedVector2Array([
		Vector2(-1.0e7, -1.0e7), Vector2(1.0e7, -1.0e7), Vector2(1.0e7, 1.0e7),
		Vector2(-1.0e7, 1.0e7),
	])
	var straddle := PackedVector2Array([
		Vector2(-600 + NavTiles.SIZE - 5, -400), Vector2(-600 + NavTiles.SIZE + 5, -400),
		Vector2(-600 + NavTiles.SIZE + 5, -390), Vector2(-600 + NavTiles.SIZE - 5, -390),
	])
	var behind := PackedVector2Array([
		Vector2(-3000, -3000), Vector2(-2990, -3000), Vector2(-2990, -2990),
		Vector2(-3000, -2990),
	])
	var outlines: Array = [huge, straddle, behind]
	t.expect_eq(
		NavTiles.bin(outlines, reaches, Vector2.ZERO),
		_full_scan(outlines, reaches, Vector2.ZERO),
		"a huge, a straddling and a far-behind outline bin as the full scan does",
	)


## The reach rect of every tile, including the baker's border.
func _reaches(tiles: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for tile: NavigationRegion2D in tiles:
		out.append((tile.get_meta(NavTiles.RECT_META) as Rect2).grow(NavTiles.BORDER))
	return out


## The original algorithm: every outline's bounds tested against every tile's reach.
func _full_scan(outlines: Array, reaches: Array[Rect2], shift: Vector2) -> Array:
	var bins: Array = []
	for _reach in reaches:
		bins.append([])
	for outline: PackedVector2Array in outlines:
		var box := NavSource.outline_bounds(outline)
		box.position -= shift
		for i in reaches.size():
			if reaches[i].intersects(box):
				bins[i].append(outline)
	return bins


func _containing(bins: Array, outline: PackedVector2Array) -> Array[int]:
	var out: Array[int] = []
	for i in bins.size():
		if bins[i].has(outline):
			out.append(i)
	return out


## Prove the district fixture exercises the border, not only tile interiors.
func _border_reached(t: TestContext, fixture: Dictionary, outlines: Array, bins: Array) -> void:
	var hits := 0
	var reaches := _reaches(fixture["tiles"])
	for outline: PackedVector2Array in outlines:
		var box := NavSource.outline_bounds(outline)
		box.position -= (fixture["district"] as Node2D).position
		for i in fixture["tiles"].size():
			var rect := fixture["tiles"][i].get_meta(NavTiles.RECT_META) as Rect2
			if not rect.intersects(box) and reaches[i].intersects(box) and bins[i].has(outline):
				hits += 1
	t.check(
		hits > 0,
		"outlines outside tile interiors but inside their borders are binned (%d)" % hits,
	)
