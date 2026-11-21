extends GameTest
## A shoved piece meets the items lying on the floor (#194 stack-a, D20, `docs/stacked-items.md`
## SI5): a chair shoved along the floor into a plate pushes it along ahead of it, it does not slide
## over or through it (a plate is on `TWIN_WALKOVER`, which a character's walk passes, not a
## piece's).

const Probe := preload("res://tests/_objects/piece_probe.gd")
const CHAIR_AT := Vector2(250, 250)
const PLATE_AT := Vector2(284, 250)


func describe() -> Dictionary:
	return {
		"name": "A shoved chair pushes a plate on the floor",
		"description": "A chair shoved along the floor into a plate on the floor moves the plate "
			+ "on ahead of it: the plate ends up shifted and the chair behind it, not over it.",
		"tags": ["furniture", "3d", "items", "stacking", "pushable"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "chair", CHAIR_AT)
	s.object(&"plate", "plate", PLATE_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for id in [&"chair", &"plate"]:
		if not t.require(await Probe.settle(t, t.object(id), 4.0), "premise: %s asleep" % id):
			return
	Knockback.push(t.object(&"chair"), Vector2(900.0, 0.0), Vector2.ZERO, 8.0)
	await t.seconds(1.2)
	var plate: Vector2 = Probe.middle(t.object(&"plate"))
	var chair: Vector2 = Probe.middle(t.object(&"chair"))
	t.check(
		plate.x - PLATE_AT.x > 4.0,
		"the plate was pushed on (%.1f px)" % (plate.x - PLATE_AT.x),
	)
	t.check(
		chair.x < plate.x,
		"the chair is behind the plate (%.1f, %.1f), not over it" % [chair.x, plate.x],
	)
	t.check(
		TwinSpace.twin_for(t.object(&"plate")).collision_layer == PhysicsLayers.TWIN_WALKOVER
			or Probe.top(t.object(&"plate")) > DoorFallConfig.step_over,
		"and it still lies flat on the walk-over layer",
	)
