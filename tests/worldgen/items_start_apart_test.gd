extends GameTest
## D20 / SI9 (#194): no two small items of a generated house start inside each
## other. Over every floorplan and three seeds (garage_home seed 7 among them, where a box stands on
## a box at one point), each pair of items whose footprints overlap in the plan is apart in height:
## one rests on the top of the other, never through it.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const SEEDS := [2, 7, 13]
## How far (px) two footprints or two heights may overlap and still count as touching.
const SLACK := 0.5


func describe() -> Dictionary:
	return {
		"name": "A house's small items start apart",
		"description": "Over every floorplan and three seeds, no two items of a house overlap in "
			+ "the plan and in height at the start: a stacked one rests on the top of the one "
			+ "under it.",
		"tags": ["worldgen", "stacking", "house", "items"],
		"timeout": 200.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-4000, -4000, 8000, 8000))


func run(t: TestContext) -> void:
	var checked := 0
	for plan_key: String in HouseDefinitions.get_all():
		for house_seed: int in SEEDS:
			var house := Houses.generated(t, plan_key, house_seed)
			checked += _check(t, "%s seed %d" % [plan_key, house_seed], house)
			house.queue_free()
			await t.frames(1)
	t.check(checked > 200, "premise: a sample of items (%d)" % checked)


## Check every pair of the items `house` placed; returns how many there are.
func _check(t: TestContext, where: String, house: Node2D) -> int:
	var items: Array = RoomItems.placed_in(house).map(
		func(entry: Dictionary) -> Node2D: return entry["node"]
	)
	var bad: Array[String] = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Node2D = items[i]
			var b: Node2D = items[j]
			if _inside_each_other(a, b):
				bad.append("%s and %s at %s" % [a.name, b.name, a.global_position.snappedf(0.1)])
	t.check(
		bad.is_empty(),
		"%s: no two items start inside each other: %s" % [where, bad.slice(0, 6)],
	)
	return items.size()


## Whether `a` and `b` overlap in the plan and in height.
func _inside_each_other(a: Node2D, b: Node2D) -> bool:
	var a_foot := Rect2(a.global_position - a.size * 0.5, a.size).grow(-SLACK)
	var b_foot := Rect2(b.global_position - b.size * 0.5, b.size).grow(-SLACK)
	if not a_foot.intersects(b_foot):
		return false
	var a_low: float = (a.rest as PieceRest).lift
	var b_low: float = (b.rest as PieceRest).lift
	var a_high := a_low + PieceHeights.top_of_spec(FurnitureSpec.of(a))
	var b_high := b_low + PieceHeights.top_of_spec(FurnitureSpec.of(b))
	return minf(a_high, b_high) - maxf(a_low, b_low) > SLACK
