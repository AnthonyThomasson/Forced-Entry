extends GameTest
## A piece of furniture at rest costs the frame nothing: its BloodSmear runs no per-frame step while
## the body sleeps (a district holds hundreds of pieces, perf/match_5v5_stress), wakes with it when
## it is shoved, and still smears the blood it drags out of a puddle then (object_smear is the same
## drag from a body that never slept).

const SPLAT_AT := Vector2(300, 200)
const SLEEP_S := 6.0


func describe() -> Dictionary:
	return {
		"name": "A sleeping piece's smear takes no per-frame step",
		"description": "A chair in a puddle falls asleep and its smear stops stepping; a shove "
			+ "wakes both, the chair smears the floor beyond the puddle, and both sleep again.",
		"tags": ["blood", "smear", "perf", "pushable"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", SPLAT_AT)


func run(t: TestContext) -> void:
	var throw := BloodThrow.new()
	throw.size = 30.0
	BloodSpawner.splat(t.world, SPLAT_AT, throw)
	var chair := t.object(&"chair") as RigidBody2D
	var smear := _smear_of(chair)
	if not t.require(smear != null, "premise: the chair has a BloodSmear"):
		return
	if not t.require(
			await t.until(func(): return chair.sleeping, SLEEP_S),
			"premise: the chair falls asleep",
	):
		return
	await t.frames(2)
	t.check(not smear.is_physics_processing(), "a sleeping chair's smear takes no per-frame step")

	chair.apply_central_impulse(Vector2(5000.0, 0.0))
	await t.frames(2)
	t.check(smear.is_physics_processing(), "a shoved chair's smear steps again")
	t.require(
			await t.until(func(): return chair.global_position.x > 460.0, 5.0),
			"the shoved chair slides out of the puddle",
	)
	var layer := BloodDecals.find(chair.get_parent())
	t.check(layer != null and layer.ribbon_count() > 0, "the shoved chair left streaks")
	t.check(
		await t.until(func(): return chair.sleeping, SLEEP_S),
		"the chair falls asleep again",
	)
	await t.frames(2)
	t.check(not smear.is_physics_processing(), "and its smear stops stepping again")


func _smear_of(body: Node) -> BloodSmear:
	for child in body.get_children():
		if child is BloodSmear:
			return child
	return null
