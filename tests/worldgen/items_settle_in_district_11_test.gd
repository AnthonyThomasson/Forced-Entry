extends GameTest
## D20 / SI9 (#194 stack-b review M1): the small items of a generated district settle where they
## were set. A bigger item stacked on a smaller one overhangs it and toppled at the start
## (district 11's stockroom: two crates on a box ended lying 17 and 37 px away); an item goes only
## on a top at least as big as its base.

const Settle := preload("res://tests/_worldgen/item_settle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A district's small items settle where they were set (seed 11)",
		"description": "After two seconds every item of district 11 (the tower stockroom's stacks) "
			+ "is asleep within a few px and a few degrees of where it was set.",
		"tags": ["worldgen", "stacking", "district", "3d", "items"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(11, "")


func run(t: TestContext) -> void:
	await Settle.check(t, "district 11", t.world, 20)
