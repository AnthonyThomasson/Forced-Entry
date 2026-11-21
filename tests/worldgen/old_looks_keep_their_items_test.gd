extends GameTest
## The emptied pieces keep their old look as items (#194 unbake-b, D21, rule 9,
## `docs/stacked-items.md` SI13): a stockroom's crate stack is two loose crates and no stack piece,
## its pallet a pallet item with four wrapped boxes on it, a kitchenette's hotplate a crate piece
## with a hotplate plate and a pan on it, and a bookshelf, shelving, linen shelf or shoe rack
## carries the books, boxes or shoes it drew. Nothing is strewn on the stockroom floor besides.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const PLANS := ["micro_flat", "corner_flat", "starter_home", "garage_home"]
const SEEDS := [2, 5, 9, 11, 13, 16]


func describe() -> Dictionary:
	return {
		"name": "Emptied pieces keep their old look as items",
		"description": "A district's stockrooms get loose crates and a pallet with boxes (no "
			+ "stack piece, nothing else on the floor); a kitchenette gets its crate, a hotplate "
			+ "and a pan; shelves carry their books, boxes and shoes.",
		"tags": ["worldgen", "stacking", "items", "district", "house", "unbake"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.district(11, "")


func run(t: TestContext) -> void:
	var seen := { "Crates": 0, "Pallet": 0, "Hotplate": 0, "Shelves": 0, "Books": 0 }
	for tower: Dictionary in DistrictReads.get_towers(t.world.district):
		_check(t, "district 11", RoomItems.placed_in(tower["node"]), seen)
	for plan_key: String in PLANS:
		if not plan_key in HouseDefinitions.get_all():
			continue
		for house_seed: int in SEEDS:
			var house := Houses.generated(t, plan_key, house_seed)
			_check(t, "%s seed %d" % [plan_key, house_seed], RoomItems.placed_in(house), seen)
			house.queue_free()
			await t.frames(1)
	for kind: String in seen:
		t.check(seen[kind] > 0, "premise: a sample of %s places (%d)" % [kind, seen[kind]])


## The items of `placed` (`RoomItems.placed_in`) grouped by the piece each stands on, checked.
func _check(t: TestContext, where: String, placed: Array, seen: Dictionary) -> void:
	var on: Dictionary = {}
	for entry: Dictionary in placed:
		if entry["on"] == null:
			t.check(
				not "Stockroom" in String(entry["room"]),
				"%s: nothing strewn on a stockroom floor (%s)" % [where, entry["key"]],
			)
			continue
		var base: Node2D = entry["on"]
		if not on.has(base):
			on[base] = []
		(on[base] as Array).append(String(entry["key"]))
	for base: Node2D in on:
		var keys: Array = on[base]
		match String(base.object_name):
			"Crates":
				seen["Crates"] += 1
				t.check(not base.solid, "%s: a crate stack is no solid piece" % where)
				t.check(keys == ["crate", "crate"], "%s: two loose crates (%s)" % [where, keys])
			"Pallet":
				seen["Pallet"] += 1
				t.check(not base.solid, "%s: a pallet place is no solid piece" % where)
				t.check(
					keys.count("pallet") == 1 and keys.count("wrapped_box") == 4,
					"%s: a pallet with four wrapped boxes (%s)" % [where, keys],
				)
			"Hotplate":
				seen["Hotplate"] += 1
				t.check(base.solid, "%s: the hotplate's crate is a piece" % where)
				t.check(
					keys == ["hob", "pan"], "%s: a hotplate and a pan on it (%s)" % [where, keys]
				)
			"Books", "Shelves", "Linen", "Shoes":
				seen["Shelves"] += 1
				var thing: String = {
					"Books": "book_stood", "Shelves": "box", "Linen": "box", "Shoes": "shoes",
				}[base.object_name]
				t.check(
					keys.all(func(key: String) -> bool: return key == thing) and keys.size() > 0,
					"%s: %s carries %s (%s)" % [where, base.object_name, thing, keys.slice(0, 4)],
				)
				if base.object_name == "Books":
					seen["Books"] += 1
