extends GameTest
## D20 / SI9 (#194): placing small items on tops and floors never moves what was there. A
## seeded house's and a district's whole tree (the furniture, clutter, neon, walls, floors and
## doors, but the items' own nodes) and the doors' openings, materials and styles are identical with
## the items on and off, because the items draw from an RNG stream of their own and run after the
## furniture.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const District := preload("res://tests/_worldgen/district_probe.gd")
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
	var kept := _without_items(District.digest(with))
	var bare := _without_items(District.digest(without))
	t.check(bare.size() > 20, "%s: the house has a tree (%d nodes)" % [where, bare.size()])
	t.expect_eq(District.first_difference(kept, bare), "", "%s: the same tree, items apart" % where)
	t.expect_eq(_doors(with), _doors(without), "%s: the same doors, each as it was" % where)
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


## What the doors of `house` are: each opening's place, its door's material and style, sorted.
func _doors(house: Node2D) -> Array:
	var out: Array = []
	for door: Dictionary in WorldGen.get_doors(house):
		var opening: Dictionary = door["opening"]
		out.append("%s %s %s" % [opening["pos"], door["material"], door["style"]])
	out.sort()
	return out
