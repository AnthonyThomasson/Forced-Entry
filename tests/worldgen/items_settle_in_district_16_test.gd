extends GameTest
## D20 / SI9 (#194 stack-b review M1): the small items of a generated district settle where they
## were set. A bigger item stacked on a smaller one overhangs it and toppled at the start
## (the review saw a desk lamp on a cabinet move 9.8 px); an item goes only
## on a top at least as big as its base.

const Settle := preload("res://tests/_worldgen/item_settle_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A district's small items settle where they were set (seed 16)",
		"description": "After two seconds every item of district 16 (the review's lamp seed) "
			+ "is asleep within a few px and a few degrees of where it was set.",
		"tags": ["worldgen", "stacking", "district", "3d", "items"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(16, "")


func run(t: TestContext) -> void:
	await Settle.check(t, "district 16", t.world, 20)
