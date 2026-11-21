extends GameTest
## D20 / SI9 (#194 stack-b): a few small items on the flat tops, on about half of them. Over a
## sample of seeded houses: of the tops that take items (a table, a desk, a counter, a shelf: what
## `ItemsCatalog.options_for` says) between 30 and 70 percent carry any, each carries 1 to
## `top_max` (a book or a plate may be stacked on one more), every item lies inside its base's
## footprint, is one of its catalogue row's kinds and rests on a body of its base's room. Boxes and
## crates stand stacked two or three high on the floor of a storage room, a garage or an office.
## The same seed gives the same items; items off gives none.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const PLANS := [
	"starter_home",
	"open_plan_home",
	"bungalow",
	"garage_home",
	"two_bed_flat",
	"office_loft",
]
const SEEDS := [2, 3, 5, 8, 13, 21]
const MIN_SHARE := 0.3
const MAX_SHARE := 0.7


func describe() -> Dictionary:
	return {
		"name": "Tops get a few items, about half of them, the same for the same seed",
		"description": "About half the flat tops of seeded houses carry 1 to 3 items, "
			+ "inside the top; storage rooms hold 2-3 high stacks of boxes and crates; the same "
			+ "seed places the same items; none with items off.",
		"tags": ["worldgen", "stacking", "determinism", "house"],
		"timeout": 120.0,
	}


func run(t: TestContext) -> void:
	var tops := 0
	var laden := 0
	var floor_stacks := 0
	var plans: Array = HouseDefinitions.get_all()
	for plan_key: String in PLANS:
		if not plan_key in plans:
			continue
		for house_seed: int in SEEDS:
			var house := Houses.generated(t, plan_key, house_seed)
			var again := Houses.generated(t, plan_key, house_seed)
			var where := "%s seed %d" % [plan_key, house_seed]
			t.expect_eq(_signature(again), _signature(house), "%s: the same items again" % where)
			var items := RoomItems.placed_in(house)
			var by_base := {}
			for item: Dictionary in items:
				if item.get("carried", false):
					continue  # Carried (unbake, D21): a row of data, not a fill.
				if item["on"] == null:
					floor_stacks += 1
					continue
				by_base[item["on"]] = (by_base.get(item["on"], []) as Array) + [item]
			tops += _tops_of(house)
			laden += by_base.size()
			_check_items(t, where, items)
			house.queue_free()
			again.queue_free()
			await t.frames(1)
	var share := float(laden) / maxf(1.0, float(tops))
	t.check(tops > 40, "a sample of tops (%d)" % tops)
	t.check(
		share >= MIN_SHARE and share <= MAX_SHARE,
		"about half the tops carry items (%d of %d, %.2f)" % [laden, tops, share],
	)
	t.check(floor_stacks > 0, "storage rooms hold floor stacks (%d)" % floor_stacks)
	await _off(t)


## How many pieces of `house` take items on top (`ItemsCatalog.options_for`), read from the
## piece's node name (its catalogue key, capitalised and uniquely numbered).
func _tops_of(house: Node2D) -> int:
	var count := 0
	for room: Node in house.get_children():
		if not String(room.name).ends_with(" Furniture"):
			continue
		for piece in room.get_children():
			var key := String(piece.name).rstrip("0123456789").to_lower().replace(" ", "_")
			var definition := ObjectDefinitions.get_definition(key)
			if (not definition.is_empty()
					and not ItemsCatalog.options_for(key, definition).is_empty()):
				count += 1
	return count


## Each item of `items` (`RoomItems.placed_in`): of its base's kinds and inside its footprint, and
## no top over `top_max` (plus the stacked plates and books).
func _check_items(t: TestContext, where: String, items: Array) -> void:
	var counts := {}
	for item: Dictionary in items:
		var node := item["node"] as Node2D
		t.check(
			node != null and node.is_inside_tree(),
			"%s: the item %s stands" % [where, item["key"]],
		)
		var base: Node2D = item["on"]
		if base == null or node == null or item.get("carried", false):
			continue  # Carried: `old_looks_keep_their_items`.
		var foot := Rect2(base.global_position - base.size * 0.5, base.size)
		t.check(
			foot.grow(0.5).has_point(node.global_position),
			"%s: %s lies on its base's footprint" % [where, item["key"]],
		)
		counts[base] = int(counts.get(base, 0)) + 1
	for base: Node in counts:
		t.check(
			counts[base] <= WorldGenItemConfig.top_max * 2,
			"%s: %s carries %d items" % [where, base.name, counts[base]],
		)


## The items as `room key x,y` lines, sorted: what two builds of one seed must agree on.
func _signature(house: Node2D) -> Array:
	var out: Array = []
	for item: Dictionary in RoomItems.placed_in(house):
		var at: Vector2 = (item["node"] as Node2D).global_position - house.global_position
		out.append("%s %s %d,%d" % [item["room"], item["key"], roundi(at.x), roundi(at.y)])
	out.sort()
	return out


## No items with `WorldGenItemConfig.enabled` off.
func _off(t: TestContext) -> void:
	WorldGenItemConfig.enabled = false
	var house := Houses.generated(t, "bungalow", 2)
	WorldGenItemConfig.enabled = true
	t.check(RoomItems.placed_in(house).is_empty(), "no items with the switch off")
	house.queue_free()
	await t.frames(1)
