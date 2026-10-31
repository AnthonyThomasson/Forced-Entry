extends GameTest
## DR4 (docs/doors.md, issue #21): front and exit doors start shut. An interior door is seeded per
## door: shut, ajar (15 to 35 degrees) or open (90), by the weights 0.6 / 0.15 / 0.25, and the same
## for a seed every time it is generated. Read through `WorldGen.get_doors` (a door's `angle()`,
## interface 24) over every floorplan and several seeds. The weights and angles are the brief's,
## kept here.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
const SHUT_SHARE := 0.6
const AJAR_SHARE := 0.15
const OPEN_SHARE := 0.25
## How far (as a share of the interior doors) the counted shares may stray from the weights.
const SHARE_SLACK := 0.08
const AJAR_FROM := 15.0
const AJAR_TO := 35.0
const OPEN_ANGLE := 90.0
## Seeds generated twice per floorplan, to see that a seed starts its doors the same way.
const REPEAT_SEEDS := 3


func describe() -> Dictionary:
	return {
		"name": "Front and exit doors start shut, interior doors shut, ajar or open",
		"description": "DR4: front and exit doors start shut; interior doors start shut, ajar (15 "
			+ "to 35 degrees) or open by the weights 0.6 / 0.15 / 0.25, the same for a seed.",
		"tags": ["worldgen", "house", "doors", "door-start-state"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	# The angle of every interior door, over every floorplan and seed.
	var interior: Array = []
	for plan_key in HouseDefinitions.get_all():
		for house_seed in range(1, Houses.SEEDS + 1):
			var built := Houses.generated(t, plan_key, house_seed)
			_check_outer_doors_shut(t, "%s seed %d" % [plan_key, house_seed], built)
			interior.append_array(_interior_angles(built))
			built.queue_free()
			await t.frames(1)
	_check_states(t, interior)
	await _check_same_per_seed(t)


## The angle of each interior door of `built`.
func _interior_angles(built: Node2D) -> Array:
	var angles: Array = []
	for entry: Dictionary in WorldGen.get_doors(built):
		var opening: Dictionary = entry["opening"]
		if not (opening["front"] or opening["exit"]):
			angles.append((entry["node"] as Door).angle())
	return angles


## Every front and exit door of `built` is shut.
func _check_outer_doors_shut(t: TestContext, where: String, built: Node2D) -> void:
	for entry: Dictionary in WorldGen.get_doors(built):
		var opening: Dictionary = entry["opening"]
		if opening["front"] or opening["exit"]:
			var angle: float = (entry["node"] as Door).angle()
			t.check(is_zero_approx(angle), "%s %s: the door starts shut, at %s degrees"
					% [where, Houses.label(opening), angle])


## The interior doors come in the three states, ajar ones between 15 and 35 degrees, by the weights.
func _check_states(t: TestContext, angles: Array) -> void:
	var shut := angles.filter(func(a: float) -> bool: return is_zero_approx(a))
	var ajar := angles.filter(func(a: float) -> bool: return a >= AJAR_FROM and a <= AJAR_TO)
	var open := angles.filter(func(a: float) -> bool: return is_equal_approx(a, OPEN_ANGLE))
	t.check(shut.size() + ajar.size() + open.size() == angles.size(),
			"every interior door starts shut, ajar (15 to 35) or open (90): %s of %s do"
				% [shut.size() + ajar.size() + open.size(), angles.size()])
	t.check(not shut.is_empty() and not ajar.is_empty() and not open.is_empty(),
			"all three states occur: %d shut, %d ajar, %d open" % [
				shut.size(),
				ajar.size(),
				open.size(),
			])
	var total := float(angles.size())
	for share: Array in [["shut", shut.size(), SHUT_SHARE], ["ajar", ajar.size(), AJAR_SHARE],
			["open", open.size(), OPEN_SHARE]]:
		t.check(absf(share[1] / total - share[2]) <= SHARE_SLACK,
				"%s doors are %.2f of the interior doors, about %.2f" % [
					share[0],
					share[1] / total,
					share[2],
				])
	ajar.sort()
	t.check(
		not ajar.is_empty() and ajar[0] < ajar[-1] - 1.0,
		"the ajar angles differ from door to door",
	)


## A seed starts every door of its house the same way each time it is generated.
func _check_same_per_seed(t: TestContext) -> void:
	for plan_key in HouseDefinitions.get_all():
		for house_seed in range(1, REPEAT_SEEDS + 1):
			var first := Houses.generated(t, plan_key, house_seed)
			var second := Houses.generated(t, plan_key, house_seed)
			t.check(not _starts(first).is_empty() and _starts(first) == _starts(second),
					"%s seed %d: the doors start the same way twice" % [plan_key, house_seed])
			first.queue_free()
			second.queue_free()
			await t.frames(1)


## Each door's place and starting angle: `{ label: angle }`.
func _starts(built: Node2D) -> Dictionary:
	var out := {}
	for entry: Dictionary in WorldGen.get_doors(built):
		out[Houses.label(entry["opening"])] = snappedf((entry["node"] as Door).angle(), 0.01)
	return out
