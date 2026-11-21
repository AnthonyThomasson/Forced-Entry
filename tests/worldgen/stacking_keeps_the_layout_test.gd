extends GameTest
## D20 / SI9 (#194 stack-b): placing small items on tops and floors never moves what was there. A
## seeded house's furniture, clutter and neon (position and size, the doors' set) and a district's
## whole tree (but the items' own nodes) are identical with the items on and off, because the items
## draw from an RNG stream of their own and run after the furniture.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const District := preload("res://tests/_worldgen/district_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
## Floorplans checked, each over `SEEDS`.
const PLANS := ["starter_home", "open_plan_home", "garage_home", "office_loft"]
const SEEDS := [1, 7, 23]
const DISTRICT_SEED := 7


func describe() -> Dictionary:
	return {
		"name": "Stacked items leave the layout, furniture and doors where they were",
		"description": "A seeded house and a district have the same furniture list and tree with "
			+ "the small items on and off; the items add nodes and move none.",
		"tags": ["worldgen", "stacking", "determinism", "district", "house"],
		"timeout": 120.0,
	}


func run(t: TestContext) -> void:
	for plan_key: String in PLANS:
		if HouseDefinitions.get_plan(plan_key).is_empty():
			t.fail("floorplan %s exists" % plan_key)
			continue
		for house_seed: int in SEEDS:
			await _house(t, "%s seed %d" % [plan_key, house_seed], plan_key, house_seed)
	await _district(t)


## One house built with items and without.
func _house(t: TestContext, where: String, plan_key: String, house_seed: int) -> void:
	var with := Houses.generated(t, plan_key, house_seed)
	WorldGenItemConfig.enabled = false
	var without := Houses.generated(t, plan_key, house_seed)
	WorldGenItemConfig.enabled = true
	t.check(RoomItems.placed_in(without).is_empty(), "%s: no items with them off" % where)
	var bare := _signature(without)
	t.check(not bare.is_empty(), "%s: the house has furniture" % where)
	t.expect_eq(_signature(with), bare, "%s: the same furniture with items on and off" % where)
	t.expect_eq(
		WorldGen.get_doors(with).size(), WorldGen.get_doors(without).size(),
		"%s: the same doors" % where,
	)
	with.queue_free()
	without.queue_free()
	await t.frames(1)


## A district built with items and without: every node of the tree but the items' own the same.
func _district(t: TestContext) -> void:
	var with := WorldGen.generate_district(DISTRICT_SEED, "", District.ENTRANCE, t.world)
	WorldGenItemConfig.enabled = false
	var without := WorldGen.generate_district(DISTRICT_SEED, "", District.ENTRANCE, t.world)
	WorldGenItemConfig.enabled = true
	var kept := _without_items(District.digest(with))
	var bare := _without_items(District.digest(without))
	t.check(bare.size() > 100, "the district has a tree (%d nodes)" % bare.size())
	t.expect_eq(kept.size(), bare.size(), "the district has as many nodes but the items'")
	t.expect_eq(District.first_difference(kept, bare), "", "the district tree is the same")
	var placed := 0
	for tower: Dictionary in DistrictReads.get_towers(with):
		placed += RoomItems.placed_in(tower["node"]).size()
	t.check(placed > 0, "the district's towers carry items (%d)" % placed)
	with.queue_free()
	without.queue_free()
	await t.frames(1)


## `lines` of a district digest but those of the items' nodes (a room's `... Items` node and what
## is under it).
func _without_items(lines: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for line in lines:
		if not " Items" in line:
			kept.append(line)
	return kept


## What a house placed that is no item: `x,y WxH` of every piece (items left out), sorted.
func _signature(house: Node2D) -> Array:
	var out: Array = []
	for node in PlanProbe.pieces_under(house):
		if not "size" in node or String(node.get_parent().name).ends_with(" Items"):
			continue
		var at: Vector2 = node.global_position - house.global_position
		var size: Vector2 = node.size
		out.append("%d,%d %dx%d" % [roundi(at.x), roundi(at.y), roundi(size.x), roundi(size.y)])
	out.sort()
	return out
