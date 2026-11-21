extends GameTest
## The emptied pieces keep their old look as items (#194 unbake-b, D21, rule 9,
## `docs/stacked-items.md` SI13): a stockroom's crate stack is two or three loose crates (by its
## place: a third stands on the pair for about half of them) and no stack piece,
## its pallet a pallet item with four wrapped boxes on it, a kitchenette's hotplate a crate piece
## with a hotplate plate and a pan on it, and a bookshelf, shelving, linen shelf or shoe rack
## carries the books, boxes or shoes it drew. Nothing is strewn on the stockroom floor besides.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const PLANS := ["micro_flat", "corner_flat", "starter_home", "garage_home"]
const SEEDS := [2, 5, 9, 11, 13, 16]
## The top (px) of a stack's two crates, and how far (px) the third's lift may be off it.
const CRATE_PAIR_TOP := 40.0
const LIFT_SLACK := 1.0


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
	var seen := {
		"Crates": 0, "Crates2": 0, "Crates3": 0, "Pallet": 0, "Hotplate": 0, "Shelves": 0,
		"Books": 0, "Tins": 0,
	}
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
				_check_crates(t, where, placed, base, seen)
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
					_holds(keys, thing),
					"%s: %s carries %s (%s)" % [where, base.object_name, thing, keys.slice(0, 4)],
				)
				seen["Books"] += int(base.object_name == "Books")
				seen["Tins"] += keys.count("paint_tin")


## The crate stack `base` with the item `keys` placed on it: two or three loose crates, no solid
## piece, and a third stands on the pair (their top, 40 px up), not through it.
func _check_crates(
	t: TestContext,
	where: String,
	placed: Array,
	base: Node2D,
	seen: Dictionary,
) -> void:
	var keys: Array = []
	var lifts: Array = []
	for entry: Dictionary in placed:
		if entry["on"] == base:
			keys.append(entry["key"])
			lifts.append((entry["node"].rest as PieceRest).lift)
	seen["Crates"] += 1
	t.check(not base.solid, "%s: a crate stack is no solid piece" % where)
	t.check(
		keys.count("crate") == keys.size() and keys.size() in [2, 3],
		"%s: two or three loose crates (%s)" % [where, keys],
	)
	seen["Crates%d" % keys.size()] = seen.get("Crates%d" % keys.size(), 0) + 1
	if keys.size() != 3:
		return
	t.check(
		absf(float(lifts.max()) - CRATE_PAIR_TOP) <= LIFT_SLACK,
		"%s: the third crate rests on the pair (lifts %s)" % [where, lifts],
	)


## Whether the item `keys` of a shelf are its `thing` (a shelf of boxes holds the odd paint tin).
func _holds(keys: Array, thing: String) -> bool:
	var allowed := [thing, "paint_tin"]
	return not keys.is_empty() and keys.all(func(key: String) -> bool: return key in allowed)
