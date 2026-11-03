extends GameTest
## Every tower of a district (#182) faces a street of its own block: its front door opens onto the
## sidewalk round its block, and past that sidewalk lies the asphalt of a street. Across seeds the
## house and the neighbours take all four facings (north, east, south, west), the seed deciding
## which. Read through `DistrictReads.get_towers` (`front` the front doorway with its `outward`) and
## `DistrictReads.get_district_street`.

const District := preload("res://tests/_worldgen/district_probe.gd")
const SEEDS := 24
## How far out of the door the probe walks, and in what steps (px): past the sidewalk and across the
## street it leads to.
const WALK_REACH := 400.0
const WALK_STEP := 8.0
## The first probe lies on the sidewalk this close to the door at most.
const ONTO_SIDEWALK := 16.0


func describe() -> Dictionary:
	return {
		"name": "Every tower faces a street of its own block, and all four facings occur",
		"description": "Each front door of a district opens onto its own block's sidewalk and then "
			+ "a street; across seeds the house and its neighbours face all four ways.",
		"tags": ["worldgen", "district", "tower", "turn", "street"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## Walk out of `tower`'s front door: onto its own block's sidewalk within `ONTO_SIDEWALK`, then onto
## a street with nothing else between.
func _check_tower(t: TestContext, label: String, tower: Dictionary, streets: Array) -> void:
	var door: Vector2 = tower["front"]["pos"]
	var out: Vector2 = tower["front"]["outward"][0]
	var first := District.piece_at(streets, door + out * ONTO_SIDEWALK)
	if not t.check(
		not first.is_empty() and first["kind"] == "sidewalk" and first["block"] == tower["block"],
		"%s: the front door at %s does not open onto its block's sidewalk (%s)"
			% [label, door, first.get("kind", "nothing")],
	):
		return
	var reached := false
	var steps := int(WALK_REACH / WALK_STEP)
	for i in range(1, steps + 1):
		var piece := District.piece_at(streets, door + out * WALK_STEP * i)
		if piece.is_empty() or piece["kind"] == "street":
			reached = not piece.is_empty()
			break
		if piece["block"] != tower["block"]:
			break
	t.check(reached, "%s: the sidewalk at %s leads to no street" % [label, door])


func run(t: TestContext) -> void:
	var house_facings := {}
	var neighbour_facings := {}
	for district_seed in range(1, SEEDS + 1):
		var district := WorldGen.generate_district(district_seed, "", District.ENTRANCE, t.world)
		var streets := DistrictReads.get_district_street(district)
		for tower: Dictionary in DistrictReads.get_towers(district):
			_check_tower(t, "seed %d block %d" % [district_seed, tower["block"]], tower, streets)
			var is_house: bool = tower["block"] == District.HOUSE_BLOCK
			var facings := house_facings if is_house else neighbour_facings
			facings[tower["front"]["outward"][0]] = true
		district.queue_free()
		await t.frames(2)
	for who in [["the house", house_facings], ["the neighbours", neighbour_facings]]:
		for facing: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			t.check(
				(who[1] as Dictionary).has(facing),
				"across %d seeds %s never faces %s" % [SEEDS, who[0], facing],
			)
