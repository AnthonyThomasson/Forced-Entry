extends GameTest
## An unarmed character's hands hang at its sides, below the shoulder height (body radii off the
## floor: relaxed 3.7, running 4 to 5.8); a hand raised to a gun grips at that height or above.

const SHOULDER_HEIGHT := 5.0


func describe() -> Dictionary:
	return {
		"name": "Hanging hands grip below the shoulders",
		"description": "Standing unarmed, the hands grip below the shoulder height; holding a "
			+ "pistol, they grip at it.",
		"tags": ["pose", "hands"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"unarmed", &"puppet", Vector2(200, 200), { "start_slot": ItemRegistry.UNARMED_SLOT })
	s.actor(&"armed", &"puppet", Vector2(500, 200), { "start_slot": 3 })


func run(t: TestContext) -> void:
	await t.seconds(1.5)
	t.check(
		t.actor(&"unarmed").anatomy.pose.arms.grip_height(0) < SHOULDER_HEIGHT,
		"unarmed hands grip below the shoulders",
	)
	t.check(
		t.actor(&"armed").anatomy.pose.arms.grip_height(0) >= SHOULDER_HEIGHT,
		"a gun's hands grip at the shoulders",
	)
