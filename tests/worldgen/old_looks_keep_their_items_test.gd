extends GameTest
## The emptied pieces keep their old look as items (#194 unbake-b, D21, rule 9,
## `docs/stacked-items.md` SI13): a stockroom's crate stack is two or three loose crates (by its
## place: a third stands on the pair for about half of them) and no stack piece,
## its pallet a pallet item with four wrapped boxes on it, a kitchenette's hotplate a crate piece
## with a hotplate plate and a pan on it, and a bookshelf, shelving, linen shelf or shoe rack
## carries the books, boxes or shoes it drew. Nothing is strewn on the stockroom floor besides.
## The home tops too (#194 unbake-a, SI14): every desk, side table, console table, nightstand,
## dresser, kitchen and kitchenette counter, island and workbench paints no props and carries
## exactly the items its row says (`HOME`), each set where the drawing had it (the row's `at`, px
## from the piece's centre in its frame, turned the way it faces), and no item of the random fill.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const PLANS := ["micro_flat", "corner_flat", "starter_home", "garage_home"]
const SEEDS := [2, 5, 9, 11, 13, 16]
## The seeds of the plans that carry no stock (the home tops are in all of them).
const HOME_SEEDS := [2, 5, 13]
## The home tops that were emptied and the items each now carries: the premise, written out here.
const HOME := {
	"desk": ["cup", "keyboard", "monitor", "papers"],
	"side_table": ["book"],
	"console_table": ["bowl", "vase"],
	"nightstand": ["book", "clock"],
	"dresser": ["book", "vase"],
	"kitchen_counter": ["cutting_board"],
	"kitchenette_counter": ["cutting_board"],
	"island": ["fruit_bowl"],
	"workbench": ["tools", "vise"],
}
## Where each home top's items were drawn: px from the piece's centre in its frame (the front
## toward +y), the old painter's props (the prop's unit point through the painter's rect inset 3
## px). Written out here, not read from the rows, so a row moved is a test that fails.
const DRAWN_AT := {
	"side_table": {
		"book": Vector2(0, 0),
	},
	"nightstand": {
		"clock": Vector2(-7.5, -4.4),
		"book": Vector2(6.1, -3),
	},
	"desk": {
		"monitor": Vector2(0, -12.3),
		"keyboard": Vector2(0, 5.3),
		"cup": Vector2(37.6, 2.2),
		"papers": Vector2(-39.8, 0),
	},
	"console_table": {
		"bowl": Vector2(-16.8, 0),
		"vase": Vector2(21, 0),
	},
	"dresser": {
		"vase": Vector2(-25.9, -4.4),
		"book": Vector2(16.3, -3),
	},
	"kitchen_counter": {
		"cutting_board": Vector2(-16.9, 4),
	},
	"island": {
		"fruit_bowl": Vector2(0, -4.9),
	},
	"kitchenette_counter": {
		"cutting_board": Vector2(-26.3, 3.3),
	},
	"workbench": {
		"tools": Vector2(-12.5, 0),
		"vise": Vector2(36.4, -1.9),
	},
}
## How far (px) a home item stands from its drawn point at the start, before it settles.
const DRAWN := 1.0
## Where the barricade's old painter drew its sandbags (px from its centre, SI15: two stacks of
## three side by side, a smaller bag on each middle one: eight in all, the middle two points twice).
const BAGS := [
	Vector2(-52.5, -9), Vector2(-49.5, -1), Vector2(-52.5, 7),
	Vector2(51.5, -9), Vector2(54.5, -1), Vector2(51.5, 7),
]
## The top (px) of a stack's two crates, and how far (px) the third's lift may be off it.
const CRATE_PAIR_TOP := 40.0
const LIFT_SLACK := 1.0


func describe() -> Dictionary:
	return {
		"name": "Emptied pieces keep their old look as items",
		"description": "The home tops carry the items they painted as props; a district's "
			+ "stockrooms get loose crates and a pallet with boxes (no stack piece, nothing else "
			+ "on the floor); a kitchenette gets its crate, a hotplate and a pan; shelves carry "
			+ "their books, boxes and shoes.",
		"tags": ["worldgen", "stacking", "items", "district", "house", "unbake"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.district(11, "")


func run(t: TestContext) -> void:
	var seen := {
		"Crates": 0, "Crates2": 0, "Crates3": 0, "Pallet": 0, "Hotplate": 0, "Shelves": 0,
		"Books": 0, "Tins": 0, "Barricade": 0, "Coats": 0,
	}
	for home: String in HOME:
		seen[home] = 0
	for tower: Dictionary in DistrictReads.get_towers(t.world.district):
		_check(t, "district 11", RoomItems.placed_in(tower["node"]), seen)
	for plan_key: String in HouseDefinitions.get_all():
		for house_seed: int in (SEEDS if plan_key in PLANS else HOME_SEEDS):
			var house := Houses.generated(t, plan_key, house_seed)
			_check(t, "%s seed %d" % [plan_key, house_seed], RoomItems.placed_in(house), seen)
			_check_home(t, "%s seed %d" % [plan_key, house_seed], house, seen)
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
			"Barricade":
				seen["Barricade"] += 1
				_check_sandbags(t, where, placed, base)
			"Coats":
				seen["Coats"] += 1
				t.expect_eq(keys, ["hat"], "%s: a coat rack carries a hat and no fill" % where)


## The barricade `base`: eight sandbags, one at each drawn point (the middle two a small bag on
## each).
func _check_sandbags(t: TestContext, where: String, placed: Array, base: Node2D) -> void:
	var bags: Array = placed.filter(
		func(entry: Dictionary) -> bool: return entry["on"] == base and entry["key"] == "sandbag"
	)
	t.expect_eq(bags.size(), 8, "%s: a barricade carries eight sandbags" % where)
	var turns := roundi(Vector2.DOWN.angle_to(base.look.facing) / (PI * 0.5))
	for point: Vector2 in BAGS:
		var want: Vector2 = base.global_position + point.rotated(turns * PI * 0.5)
		var near := bags.filter(
			func(entry: Dictionary) -> bool:
				return (entry["node"] as Node2D).global_position.distance_to(want) <= DRAWN
		)
		t.check(not near.is_empty(), "%s: a sandbag is where it was drawn (%s)" % [where, point])


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


## Every home top of `house` (a piece of a `<room> Furniture` node named in `HOME`): it paints no
## props, carries what `HOME` says (nothing of the random fill) and each item is at its drawn point.
func _check_home(t: TestContext, where: String, house: Node2D, seen: Dictionary) -> void:
	var placed := RoomItems.placed_in(house)
	for room: Node in house.get_children():
		if not String(room.name).ends_with(" Furniture"):
			continue
		for piece: Node2D in room.get_children():
			var key := _home_key(piece)
			if key == "":
				continue
			seen[key] += 1
			var label := "%s: %s" % [where, piece.name]
			t.check(
				not (piece.look.art_opts as Dictionary).has("props"), "%s paints no props" % label
			)
			var items: Array = placed.filter(
				func(entry: Dictionary) -> bool: return entry["on"] == piece
			)
			var keys: Array = items.map(func(entry: Dictionary) -> String: return entry["key"])
			keys.sort()
			t.expect_eq(keys, HOME[key], "%s carries its items and no fill" % label)
			_check_drawn(t, label, key, piece, items)


## The catalogue key of the home top `piece` is (its node is named by its key), else "".
func _home_key(piece: Node2D) -> String:
	var stem := String(piece.name).rstrip("0123456789")
	for key: String in HOME:
		if stem == key.capitalize():
			return key
	return ""


## Each row of the home top `piece`'s `carries` has its item at the point it was drawn.
func _check_drawn(
	t: TestContext,
	label: String,
	key: String,
	piece: Node2D,
	items: Array,
) -> void:
	var turns := roundi(Vector2.DOWN.angle_to(piece.look.facing) / (PI * 0.5))
	for row: Dictionary in ObjectDefinitions.get_definition(key)["carries"]:
		t.expect_eq(row["at"], DRAWN_AT[key][row["key"]], "%s: its row's point" % label)
		var want: Vector2 = piece.global_position + (DRAWN_AT[key][row["key"]] as Vector2).rotated(
			turns * PI * 0.5
		)
		var found := false
		for entry: Dictionary in items:
			if entry["key"] == row["key"]:
				var node: Node2D = entry["node"]
				found = found or node.global_position.distance_to(want) <= DRAWN
		t.check(found, "%s: the %s is where it was drawn" % [label, row["key"]])
