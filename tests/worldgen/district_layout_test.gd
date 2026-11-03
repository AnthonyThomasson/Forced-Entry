extends GameTest
## A district (#182): `WorldGen.generate_district(seed, force_plan, front_entrance_world, parent)`
## is a 3 x 3 grid of blocks with one tower each, asphalt streets with sidewalks between every pair
## of neighbouring blocks and round the grid, and one closed ring of roofless shells past the outer
## street. The centre tower is the house: the forced plan if there is one (a house plan or a tower
## plan), else a tower plan; its front door lands on `front_entrance_world`. One seed reproduces the
## whole district. Neighbours stand further than 160 px (twice the default `invader_margin`) from
## the house's room bounds, so the invaders' outdoors ring never reaches into one.
##
## Reads (interface 1): `house_of`, `district_rooms` (the house's keys plain, a neighbour's keyed
## `<block>:<key>`), and the test reads `get_towers` (`{ block, plan, turn, node, rect, front }`),
## `get_shells` (`{ rect, node, style }`) and `get_district_street` (`{ kind, rect, node, block }`).

const District := preload("res://tests/_worldgen/district_probe.gd")
const SEEDS := [1, 2, 3]
const SHELLS := 16
## Twice the default `invader_margin` (80): the spec's number, not read from the code.
const OUTDOORS_RING := 160.0
## How near the shells of the ring stand to a neighbour for the ring to be closed.
const SHELL_TOUCH := 48.0


func describe() -> Dictionary:
	return {
		"name": "A district is nine towers on a grid, streets between and round, and a shell ring",
		"description": "Same seed, same district: 3 x 3 blocks with a tower each, the house in the "
			+ "centre with its front door on the entrance, streets between and round the grid, a "
			+ "closed ring of shells beyond them, neighbours clear of the invaders' ring.",
		"tags": ["worldgen", "district", "tower", "street", "shell"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## A district of `district_seed` (a `force_plan` house or tower plan if given) under the test world.
func _build(t: TestContext, district_seed: int, force_plan: String = "") -> Node2D:
	return WorldGen.generate_district(district_seed, force_plan, District.ENTRANCE, t.world)


## The tower of `towers` in `block`.
func _tower(towers: Array, block: int) -> Dictionary:
	for tower: Dictionary in towers:
		if tower["block"] == block:
			return tower
	return {}


## The shortest distance between two rects (0 if they touch or overlap).
func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()


## The towers sit on a 3 x 3 grid: each block's tower is east of its western neighbour's and south
## of its northern one's.
func _check_grid(t: TestContext, label: String, towers: Array) -> void:
	if not t.require(
		towers.size() == District.GRID * District.GRID,
		"%s: %d towers" % [label, towers.size()],
	):
		return
	for block in District.GRID * District.GRID:
		var tower := _tower(towers, block)
		if not t.check(not tower.is_empty(), "%s: a tower in block %d" % [label, block]):
			continue
		t.check(
			tower["node"] is Node2D and (tower["rect"] as Rect2).has_area(),
			"%s: block %d has a built tower" % [label, block],
		)
		if block % District.GRID > 0:
			_check_beside(t, label, [_tower(towers, block - 1), tower], true)
		if block >= District.GRID:
			_check_beside(t, label, [_tower(towers, block - District.GRID), tower], false)


## Tower `later` lies wholly east (`across`) or south of tower `earlier`.
func _check_beside(
	t: TestContext,
	label: String,
	pair: Array,
	across: bool,
) -> void:
	var a: Rect2 = pair[0]["rect"]
	var b: Rect2 = pair[1]["rect"]
	t.check(
		a.end.x < b.position.x if across else a.end.y < b.position.y,
		"%s: block %d is not %s of block %d" % [
			label,
			pair[1]["block"],
			"east" if across else "south",
			pair[0]["block"],
		],
	)


## The sidewalk round block `block`: the bounds of the tiles it is laid in.
func _walk(streets: Array, block: int) -> Rect2:
	var walk := Rect2()
	for piece: Dictionary in streets:
		if piece["kind"] == "sidewalk" and piece["block"] == block:
			walk = piece["rect"] if walk == Rect2() else walk.merge(piece["rect"])
	return walk


## Every tower stands in the pavement of its own block, and a street crosses the gap between every
## pair of neighbouring blocks' pavements and runs round the grid.
func _check_streets(t: TestContext, label: String, towers: Array, streets: Array) -> void:
	for block in District.GRID * District.GRID:
		var walk := _walk(streets, block)
		t.check(
			walk.encloses(_tower(towers, block)["rect"]),
			"%s: the tower of block %d is off its sidewalk %s" % [label, block, walk],
		)
		if block % District.GRID + 1 < District.GRID:
			var east := _walk(streets, block + 1)
			var mid := Vector2((walk.end.x + east.position.x) * 0.5, walk.get_center().y)
			t.check(
				District.covered(streets, mid, "street"),
				"%s: no street between blocks %d and %d" % [label, block, block + 1],
			)
		if block + District.GRID < District.GRID * District.GRID:
			var south := _walk(streets, block + District.GRID)
			var mid := Vector2(walk.get_center().x, (walk.end.y + south.position.y) * 0.5)
			t.check(
				District.covered(streets, mid, "street"),
				"%s: no street between blocks %d and %d" % [label, block, block + District.GRID],
			)
	# Round the grid: beyond the outermost pavements, on each side.
	var all := _walk(streets, 0).merge(_walk(streets, District.GRID * District.GRID - 1))
	for p: Vector2 in [
		Vector2(all.get_center().x, all.position.y - 40.0),
		Vector2(all.get_center().x, all.end.y + 40.0),
		Vector2(all.position.x - 40.0, all.get_center().y),
		Vector2(all.end.x + 40.0, all.get_center().y),
	]:
		t.check(
			District.covered(streets, p, "street"),
			"%s: no street round the grid at %s" % [label, p],
		)


## The ring of shells: 16 closed buildings, each past the streets, each touching two others.
func _check_shells(t: TestContext, label: String, streets: Array, shells: Array) -> void:
	if not t.require(
		shells.size() == SHELLS,
		"%s: %d shells, not %d" % [label, shells.size(), SHELLS],
	):
		return
	for shell: Dictionary in shells:
		var rect: Rect2 = shell["rect"]
		t.check(
			not streets.any(func(s: Dictionary) -> bool: return rect.intersects(s["rect"])),
			"%s: the shell at %s lies on a street" % [label, rect],
		)
		var touching := shells.filter(
			func(other: Dictionary) -> bool:
				return other != shell and _gap(rect, other["rect"]) <= SHELL_TOUCH,
		)
		t.check(touching.size() >= 2,
			"%s: the shell at %s touches %d neighbours (the ring is open)"
				% [label, rect, touching.size()])


func _check_house(t: TestContext, label: String, district: Node2D, towers: Array) -> void:
	var house := WorldGen.house_of(district)
	var centre := _tower(towers, District.HOUSE_BLOCK)
	t.check(house != null and house == centre["node"], "%s: the house is the centre tower" % label)
	var fronts := WorldGen.get_openings(house).filter(
		func(o: Dictionary) -> bool: return o["front"],
	)
	t.check(
		fronts.size() == 1 and (fronts[0]["pos"] as Vector2).distance_to(District.ENTRANCE) < 0.5,
		"%s: the house's front door is on the entrance %s" % [label, District.ENTRANCE],
	)
	t.check(
		WorldGen.get_rooms(house) == WorldGen.get_rooms(centre["node"]),
		"%s: get_rooms reads the house's rooms" % label,
	)
	# The rooms the district reports: the house's keys plain, a neighbour's `<block>:<key>`.
	var rooms := WorldGen.district_rooms(district)
	var keys := rooms.map(func(r: Dictionary) -> String: return r["key"])
	for room: Dictionary in WorldGen.get_rooms(house):
		t.check(
			keys.has(room["key"]),
			"%s: the house's room %s is in district_rooms" % [label, room["key"]],
		)
	for tower: Dictionary in towers:
		if tower["block"] == District.HOUSE_BLOCK:
			continue
		for room: Dictionary in WorldGen.get_rooms(tower["node"]):
			var key := "%d:%s" % [tower["block"], room["key"]]
			t.check(keys.has(key), "%s: %s is not in district_rooms" % [label, key])
	var unique := {}
	for key in keys:
		unique[key] = true
	t.check(unique.size() == keys.size(), "%s: district_rooms has duplicate keys" % label)


## Every room of every neighbour is further than the invaders' outdoors ring from the house's rooms.
func _check_clearance(t: TestContext, label: String, district: Node2D, towers: Array) -> void:
	var bounds := WorldGen.bounds(WorldGen.get_rooms(WorldGen.house_of(district)))
	var neighbours := towers.filter(
		func(x: Dictionary) -> bool: return x["block"] != District.HOUSE_BLOCK,
	)
	for tower: Dictionary in neighbours:
		for room: Dictionary in WorldGen.get_rooms(tower["node"]):
			var gap := _gap(bounds, room["rect"])
			t.check(
				gap > OUTDOORS_RING,
				"%s: %s in block %d is %.0f px from the house (the ring is %.0f)"
					% [label, room["key"], tower["block"], gap, OUTDOORS_RING],
			)


## The district `a` and `b`, built from one seed, are the same.
func _check_same(t: TestContext, label: String, a: Node2D, b: Node2D) -> void:
	var towers_a := DistrictReads.get_towers(a)
	var towers_b := DistrictReads.get_towers(b)
	if not t.require(towers_a.size() == towers_b.size(), "%s: the same number of towers" % label):
		return
	for i in towers_a.size():
		t.check(
			_describe(towers_a[i]) == _describe(towers_b[i]),
			"%s: tower %d differs between two builds of one seed" % [label, i],
		)
	t.check(
		_rects(DistrictReads.get_shells(a)) == _rects(DistrictReads.get_shells(b)),
		"%s: the shells differ between two builds of one seed" % label,
	)
	var streets_a := DistrictReads.get_district_street(a)
	t.check(
		_rects(streets_a) == _rects(DistrictReads.get_district_street(b)),
		"%s: the streets differ between two builds of one seed" % label,
	)
	var difference := District.first_difference(District.digest(a), District.digest(b))
	t.check(
		difference == "",
		"%s: the trees differ between two builds of one seed: %s" % [label, difference],
	)


## What makes a tower itself: its plan, turn, rect, rooms and doorways.
func _describe(tower: Dictionary) -> Array:
	return [
		tower["plan"],
		tower["turn"],
		tower["rect"],
		WorldGen.get_rooms(tower["node"]),
		WorldGen.get_openings(tower["node"]),
	]


## The rects of `pieces` (`{ rect }` dicts).
func _rects(pieces: Array) -> Array:
	return pieces.map(func(piece: Dictionary) -> Rect2: return piece["rect"])


## The plan and turn of each tower of `towers`, as one string.
func _signature(towers: Array) -> String:
	return str(towers.map(func(tw: Dictionary) -> String: return "%s%d" % [tw["plan"], tw["turn"]]))


func run(t: TestContext) -> void:
	var seen_layouts := {}
	for district_seed in SEEDS:
		var label := "seed %d" % district_seed
		var district := _build(t, district_seed)
		if not t.require(district != null, "%s builds" % label):
			return
		var towers := DistrictReads.get_towers(district)
		var streets := DistrictReads.get_district_street(district)
		_check_grid(t, label, towers)
		_check_streets(t, label, towers, streets)
		_check_shells(t, label, streets, DistrictReads.get_shells(district))
		_check_house(t, label, district, towers)
		_check_clearance(t, label, district, towers)
		t.check(
			TowerDefinitions.get_all().has(_tower(towers, District.HOUSE_BLOCK)["plan"]),
			"%s: an unforced house is a tower plan" % label,
		)
		for tower: Dictionary in towers:
			t.check(
				(TowerDefinitions.get_all().has(tower["plan"])
					or tower["block"] == District.HOUSE_BLOCK),
				"%s: block %d drew a non-tower plan" % [label, tower["block"]],
			)
		var again := _build(t, district_seed)
		_check_same(t, label, district, again)
		seen_layouts[_signature(towers)] = true
		district.queue_free()
		again.queue_free()
		await t.frames(2)
	t.check(seen_layouts.size() > 1, "different seeds make different districts")
	# A forced house plan, and a forced tower plan, become the centre tower.
	for forced in ["garage_home", "noodle_tower"]:
		var district := _build(t, 4, forced)
		var centre := _tower(DistrictReads.get_towers(district), District.HOUSE_BLOCK)
		t.check(
			centre["plan"] == forced,
			"the forced %s is the house (got %s)" % [forced, centre["plan"]],
		)
		district.queue_free()
		await t.frames(2)
