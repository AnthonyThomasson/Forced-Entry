extends GameTest
## `FadeBox.strip_entry`, the question the wall fade asks at the near top-down pitch (#193 phase
## 2b): where along the line from a focus toward the camera, grown across it by the character's half
## width only, a wall's footprint is first met. Worked by hand on a wall 200 long and 8 thick
## centred 12 px along the line (its near face at 8): a strip of half width 14 meets it at 8; a wall
## beside the line, wider than the strip, misses; one just clipping the strip's edge is met; one
## behind the focus is -1; the focus inside the footprint gives 0; and the strip is not grown ahead.


func describe() -> Dictionary:
	return {
		"name": "The wall fade's strip meets a wall across the line, not ahead of it",
		"description": "strip_entry is the near face along the line for a wall in the way, -1 for "
			+ "one beside the strip or behind the focus, 0 from inside, and a turned wall too.",
		"tags": ["mirror", "3d", "render", "wall-fade"],
		"timeout": 4.0,
	}


func run(t: TestContext) -> void:
	var diagonal := Vector2(1.0, 1.0)
	# [what, box centre, local x axis, half sizes, heading, expected along]
	var cases := [
		["a wall in the way: its near face", Vector2(0, 12), Vector2.RIGHT, Vector2(100, 4),
			Vector2.DOWN, 8.0],
		["the strip is not grown ahead: 26, not 12", Vector2(0, 30), Vector2.RIGHT,
			Vector2(100, 4), Vector2.DOWN, 26.0],
		["a wall beside the strip is missed", Vector2(200, 12), Vector2.RIGHT, Vector2(40, 4),
			Vector2.DOWN, -1.0],
		["one over the strip's edge (x 10..90) is met", Vector2(50, 12), Vector2.RIGHT,
			Vector2(40, 4), Vector2.DOWN, 8.0],
		["one starting past the strip (x 20..100) is missed", Vector2(60, 12), Vector2.RIGHT,
			Vector2(40, 4), Vector2.DOWN, -1.0],
		["a wall behind the focus is missed", Vector2(0, -20), Vector2.RIGHT, Vector2(100, 4),
			Vector2.DOWN, -1.0],
		["a footprint round the focus is 0", Vector2.ZERO, Vector2.RIGHT, Vector2(30, 30),
			Vector2.DOWN, 0.0],
		["a wall turned 45 degrees is met where its near face reaches the strip's far edge (0.343)",
			Vector2(0, 20), diagonal, Vector2(100, 4), Vector2.DOWN, 6.0 - 4.0 * sqrt(2.0)],
		["and along another heading", Vector2(30, 0), Vector2.DOWN, Vector2(100, 4),
			Vector2.RIGHT, 26.0],
	]
	for c: Array in cases:
		var box := _box(c[1], c[2], c[3])
		t.expect_near(box.strip_entry(Vector2.ZERO, c[4], 14.0), c[5], 0.001, c[0])


## A footprint centred on `at`, its local x axis `axis`, half sizes `half`, 96 tall.
func _box(at: Vector2, axis: Vector2, half: Vector2) -> FadeBox:
	var box := FadeBox.new()
	box.centre = at
	box.axis = axis.normalized()
	box.half = half
	box.bound = half.length()
	box.top = 96.0
	return box
