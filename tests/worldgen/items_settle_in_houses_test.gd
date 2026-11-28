extends GameTest
## D20 / SI9 (#194): the small items of generated houses settle where they were
## set (seed 16 had a desk lamp topple off a cabinet). Over a sample of floorplans and seeds, one
## house at a time in an arena: every item is asleep within a few px and degrees after two seconds.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const Settle := preload("res://tests/_worldgen/item_settle_probe.gd")
const SEEDS := [2, 5, 9, 13, 16, 21]


func describe() -> Dictionary:
	return {
		"name": "A house's small items settle where they were set",
		"description": "Over every floorplan and six seeds (16 among them), one house at a time: "
			+ "each item is asleep within a few px and degrees of where it was set after two "
			+ "seconds.",
		"tags": ["worldgen", "stacking", "house", "3d", "items"],
		"timeout": 400.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-4000, -4000, 8000, 8000))


func run(t: TestContext) -> void:
	var plans: Array = HouseDefinitions.get_all()
	var checked := 0
	for plan_key: String in plans:
		for house_seed: int in SEEDS:
			var house := Houses.generated(t, plan_key, house_seed)
			checked += await Settle.check(t, "%s seed %d" % [plan_key, house_seed], house, 0)
			house.queue_free()
			await t.frames(1)
	t.check(checked > 100, "a sample of items (%d)" % checked)
