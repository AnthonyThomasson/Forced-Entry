extends GameTest
## DR4 (docs/doors.md, issue #21): the test option `worldgen.doors_open` starts every door of a
## generated house fully open (90 degrees), the front and the exit doors too; without it they start
## as DR4 says (`worldgen/door_start_state`: front and exit shut). Read through `WorldGen.get_doors`
## (a door's `angle()`, interface 24) over a few floorplans and seeds.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const OPEN_ANGLE := 90.0
const PLANS := ["garage_home", "two_bed_flat", "corner_flat"]
const SEEDS := [1, 2, 3]


func describe() -> Dictionary:
	return {
		"name": "The doors-open option starts every door of a house open",
		"description": "With the test option on, every door of a generated house, front and exit "
			+ "ones too, starts fully open.",
		"tags": ["worldgen", "house", "doors", "door-start-state"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"worldgen.doors_open", true)


func run(t: TestContext) -> void:
	var counts := { "outer": 0, "doors": 0 }
	for plan_key in PLANS:
		for house_seed in SEEDS:
			var built := Houses.generated(t, plan_key, house_seed)
			_check_open(t, "%s seed %d" % [plan_key, house_seed], built, counts)
			built.queue_free()
			await t.frames(1)
	t.require(
		counts["outer"] > 0 and counts["doors"] > counts["outer"],
		"premise: front or exit and interior doors were built",
	)


## Every door of `built` starts open; `counts` tallies the doors and the front or exit ones.
func _check_open(t: TestContext, where: String, built: Node2D, counts: Dictionary) -> void:
	for entry: Dictionary in WorldGen.get_doors(built):
		var opening: Dictionary = entry["opening"]
		var angle: float = (entry["node"] as Door).angle()
		counts["doors"] += 1
		counts["outer"] += 1 if (opening["front"] or opening["exit"]) else 0
		t.check(
			is_equal_approx(angle, OPEN_ANGLE),
			"%s %s: the door starts open, at %s degrees" % [where, Houses.label(opening), angle],
		)
