extends GameTest
## A built house with its small items (#194 stack-b, D20, `docs/stacked-items.md` SI6): the boxes
## and crates stacked on a garage floor are holes in the nav map like any piece, each stack of
## them a closed spot; an item on a table sits in the table's hole, a plate or a cup lying on the
## floor (within a step) is none, and the holes the cache keeps equal a full re-cut with all of
## them there, also after a table that carries items is moved and they slide off it.

const SEED := 7
const PLAN := "garage_home"
const CLEAR := 24.0


func describe() -> Dictionary:
	return {
		"name": "Items in a built house carve like pieces",
		"description": "In a generated house the floor stacks of boxes and crates are nav holes "
			+ "and the map is closed under them; a walk-over plate adds no hole, a crate does; "
			+ "the holes equal a full re-cut, after a loaded table is moved too.",
		"tags": ["navigation", "items", "stacking", "house", "furniture"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED, PLAN)
	s.switch(&"nav.rebake", false)


## Whether some hole of `holes` holds `point`.
func _carved(holes: Array, point: Vector2) -> bool:
	return holes.any(
		func(hole: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(point, hole)
	)


## The items of `placed` (`RoomItems.placed_in`) that stand on the floor or on one that does.
func _on_the_floor(placed: Array) -> Array[Node2D]:
	var base_of := {}
	for item: Dictionary in placed:
		base_of[item["node"]] = item["on"]
	var out: Array[Node2D] = []
	for item: Dictionary in placed:
		var below: Variant = item["on"]
		while below != null and base_of.has(below):
			below = base_of[below]
		if below == null:
			out.append(item["node"])
	return out


func run(t: TestContext) -> void:
	var house: Node2D = t.world.get("house")
	await t.frames(5)
	var placed := RoomItems.placed_in(house)
	var stacked := _on_the_floor(placed)
	if not t.require(stacked.size() >= 2, "a floor stack stands (%d items)" % stacked.size()):
		return
	var holes := NavBuilder.furniture_holes(house)
	t.check(holes == NavHoles.plain(house), "the holes equal a full re-cut with the items there")
	var map := t.world.get_world_2d().navigation_map
	t.require(NavBuilder.ready(map), "the nav map is baked")
	for node in stacked:
		var at := node.global_position
		t.check(not NavHoles.cut(node).is_empty(), "%s is cut like a piece" % node.name)
		t.check(_carved(holes, at), "%s stands in a nav hole" % node.name)
	var bottom: Node2D = stacked[0]
	var off := NavBuilder.snap(map, bottom.global_position).distance_to(bottom.global_position)
	t.check(off > 6.0, "the baked map is closed under %s (%.1f px)" % [bottom.name, off])
	var on_tops := 0
	for item: Dictionary in placed:
		if item["on"] != null and not stacked.has(item["node"]):
			on_tops += 1
			var at: Vector2 = (item["node"] as Node2D).global_position
			t.check(_carved(holes, at), "%s on a top sits in its base's hole" % item["key"])
	t.check(on_tops > 0, "the house has small items on its tops (%d)" % on_tops)
	await _floor_items(t, house, map, holes)
	await _moved_table(t, house, placed, stacked)


## A plate and a cup set on the floor of the house add no hole; a crate adds one.
func _floor_items(t: TestContext, house: Node2D, map: RID, holes: Array) -> void:
	var spot := _clear_floor(map, holes)
	if not t.require(spot != Vector2.INF, "a clear patch of floor"):
		return
	ObjectFactory.spawn(ObjectDefinitions.get_definition("plate"), spot, house)
	ObjectFactory.spawn(ObjectDefinitions.get_definition("cup"), spot + Vector2(10, 0), house)
	await t.frames(3)
	var with_flat := NavBuilder.furniture_holes(house)
	t.check(with_flat.size() == holes.size(), "a plate and a cup add no hole")
	ObjectFactory.spawn(ObjectDefinitions.get_definition("crate"), spot + Vector2(0, 12), house)
	await t.frames(3)
	var with_crate := NavBuilder.furniture_holes(house)
	t.check(with_crate.size() == holes.size() + 1, "a crate adds one")
	t.check(with_crate == NavHoles.plain(house), "and the holes equal a full re-cut")


## A point of the baked map at least `CLEAR` px from every hole, or INF.
func _clear_floor(map: RID, holes: Array) -> Vector2:
	for k in 200:
		var point := NavigationServer2D.map_get_random_point(map, 1, true)
		var clear := true
		for hole: PackedVector2Array in holes:
			if Geometry2D.is_point_in_polygon(point, hole):
				clear = false
				break
			for p in hole:
				if p.distance_to(point) < CLEAR:
					clear = false
					break
			if not clear:
				break
		if clear:
			return point
	return Vector2.INF


## A table with items on it is moved: the items slide off, each a cut of its own, and the holes
## (the cache) still equal a full re-cut once they have, and after they rest.
func _moved_table(t: TestContext, house: Node2D, placed: Array, stacked: Array[Node2D]) -> void:
	var table: Node2D = null
	for item: Dictionary in placed:
		if item["on"] != null and not stacked.has(item["node"]):
			table = item["on"]
			break
	if not t.require(table != null, "a table that carries items"):
		return
	NavBuilder.furniture_holes(house)
	table.global_position += Vector2(23.0, -11.0)
	table.rotation += 0.4
	for k in 3:
		await t.frames(20)
		t.check(
			NavBuilder.furniture_holes(house) == NavHoles.plain(house),
			"after the loaded table moved the holes equal a re-cut (%d frames on)" % ((k + 1) * 20),
		)
