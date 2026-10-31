extends GameTest
## DR1 (docs/doors.md): every floorplan's doorway is 52 px wide inside the house and 60 px for the
## front and exit doorways, in both mirror states, read through the published
## `WorldGen.get_openings` of a generated house. The widths are the brief's numbers, kept here as
## the spec's own copy.

const INSIDE_WIDTH := 52.0
const FRONT_AND_EXIT_WIDTH := 60.0
## Seeds tried per floorplan, until both mirror states have been seen.
const SEEDS := 40
## Keeps each house clear of the test arena.
const FAR_AWAY := Vector2(5000, 5000)


func describe() -> Dictionary:
	return {
		"name": "Doorways are 52 px inside and 60 px at the front and exits",
		"description": "DR1: every floorplan, in both mirror states, reports interior doorways "
			+ "52 px wide and front / exit doorways 60 px wide.",
		"tags": ["worldgen", "house", "doorway", "doors"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


## True when the house was mirrored: the plan's front doorway sits at its authored x only
## unmirrored.
func _mirrored(plan: Dictionary, house: Node2D, openings: Array) -> bool:
	var front_local := Vector2.ZERO
	for opening in openings:
		if opening["front"]:
			front_local = (opening["pos"] as Vector2) - house.position
	var authored_x := 0.0
	for opening in plan["openings"]:
		if opening.get("front", false):
			authored_x = (opening["pos"] as Vector2).x
	return not is_equal_approx(front_local.x, authored_x)


func run(t: TestContext) -> void:
	for plan_key in HouseDefinitions.get_all():
		var plan := HouseDefinitions.get_plan(plan_key)
		var seen := {}
		for house_seed in range(1, SEEDS + 1):
			var house := WorldGen.generate(house_seed, plan_key, FAR_AWAY, t.world)
			var openings := WorldGen.get_openings(house)
			var mirrored := _mirrored(plan, house, openings)
			seen[mirrored] = true
			var label := "%s seed %d (%s)" % [
				plan_key,
				house_seed,
				"mirrored" if mirrored else "plain",
			]
			_check_widths(t, label, openings)
			house.queue_free()
			await t.frames(1)
			if seen.size() == 2 and house_seed >= 6:
				break
		t.check(seen.size() == 2, "%s: both mirror states were generated" % plan_key)


## Every doorway of one generated house is the width the brief gives its kind.
func _check_widths(t: TestContext, label: String, openings: Array) -> void:
	t.check(not openings.is_empty(), "%s reports doorways" % label)
	for opening in openings:
		var outer: bool = opening["front"] or opening["exit"]
		var want := FRONT_AND_EXIT_WIDTH if outer else INSIDE_WIDTH
		t.check(
			is_equal_approx(opening["width"], want),
			"%s: doorway at %s is %s px wide, expected %s"
				% [label, opening["pos"], opening["width"], want],
		)
