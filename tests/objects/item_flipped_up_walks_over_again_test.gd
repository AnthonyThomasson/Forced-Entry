extends GameTest
## A walk-over item is an obstacle only while it stands up (#194, D20,
## `docs/stacked-items.md` SI4): a plate flicked up at one rim by a real impulse tumbles, and while
## it stands taller than a step it is on `TWIN_WORLD` (a walker meets it); once it lies flat again
## it is back on `TWIN_WALKOVER` and no walker meets it.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const AT := Vector2(300, 250)
## The impulse up (per kg: a speed, px/s) at a rim of the plate (px from its centre).
const FLICK := Vector3(0.0, 1.0, 0.0)
const SPEED := 150.0
const RIM := 6.0
const FRAMES := 120


func describe() -> Dictionary:
	return {
		"name": "A plate flicked up is an obstacle until it lies flat again",
		"description": "A plate on the floor is flicked up at its rim and tumbles: while it "
			+ "stands over a step it is on the world layer, and flat again it is back on the "
			+ "walk-over layer and asleep.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"plate", "plate", AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var plate: Node2D = t.object(&"plate")
	await t.frames(3)
	if not t.require(await Probe.settle(t, plate, 4.0), "premise: the plate lies asleep"):
		return
	var body := Probe.body(plate)
	t.require(
		body.collision_layer == PhysicsLayers.TWIN_WALKOVER, "premise: it is on the walk-over layer"
	)
	body.apply_impulse(FLICK * body.mass * SPEED, Vector3(RIM, 0.0, 0.0) * RenderConfig.unit)
	var risen := 0
	var tallest := 0.0
	for i in FRAMES:
		await t.frames(1)
		tallest = maxf(tallest, Probe.top(plate))
		if body.collision_layer == PhysicsLayers.TWIN_WORLD:
			risen += 1
	t.check(
		risen > 0, "while it tumbled it was on the world layer (%d frames, up to %.1f px)" % [
			risen,
			tallest,
		]
	)
	t.check(await Probe.settle(t, plate, 6.0), "it lies asleep again")
	t.check(
		Probe.top(plate) <= DoorFallConfig.step_over,
		"lying within a step (%.1f px)" % Probe.top(plate),
	)
	t.check(
		body.collision_layer == PhysicsLayers.TWIN_WALKOVER,
		"and it is back on the walk-over layer (%d)" % body.collision_layer,
	)
	t.check(
		(body.collision_mask & PhysicsLayers.TWIN_CHARACTER) == 0,
		"where a character no longer meets it",
	)
