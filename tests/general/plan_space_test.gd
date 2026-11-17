extends GameTest
## `PlanSpace`, the plan <-> 3D helper (#194, D4): AI, world generation and most tests keep a
## `Vector2` that means plan space (x, z); this lifts one to a `Vector3` (x, height, z) and back,
## on the one scale `RenderConfig.unit` and the mirror's mapping, `(x, y)` -> `(x, 0, y) * unit`.


func describe() -> Dictionary:
	return {
		"name": "Plan space: a Vector2 lifts to (x, h, y) and back, on the mirror's scale",
		"description": "PlanSpace.lift / plan_of / height_of round-trip at any "
			+ "RenderConfig.unit and agree with the mirror's lift of a 2D body.",
		"tags": ["heights", "3d", "plan"],
		"timeout": 4.0,
	}


func run(t: TestContext) -> void:
	var saved := RenderConfig.unit
	for unit: float in [1.0, 0.5, 2.0]:
		RenderConfig.unit = unit
		_round_trip(t, unit)
		_mirror(t, unit)
		_transforms(t, unit)
	RenderConfig.unit = saved


func _round_trip(t: TestContext, unit: float) -> void:
	var at := Vector2(123.5, -47.25)
	var lifted := PlanSpace.lift(at, 30.0)
	t.expect_near(lifted.x, at.x * unit, 0.0001, "x lifts to x (x%.1f)" % unit)
	t.expect_near(lifted.y, 30.0 * unit, 0.0001, "the height is the middle axis (x%.1f)" % unit)
	t.expect_near(lifted.z, at.y * unit, 0.0001, "y lifts to z (x%.1f)" % unit)
	t.check(PlanSpace.plan_of(lifted).is_equal_approx(at), "plan_of undoes lift (x%.1f)" % unit)
	t.expect_near(PlanSpace.height_of(lifted), 30.0, 0.0001, "height_of undoes lift (x%.1f)" % unit)
	t.check(
		PlanSpace.lift(at).is_equal_approx(Vector3(at.x, 0.0, at.y) * unit),
		"no height is the ground point (x%.1f)" % unit,
	)
	var back := PlanSpace.lift(
		PlanSpace.plan_of(Vector3(7.0, 3.0, -9.0)),
		PlanSpace.height_of(Vector3(7.0, 3.0, -9.0)),
	)
	t.check(
		back.is_equal_approx(Vector3(7.0, 3.0, -9.0)),
		"3D -> plan + height -> 3D (x%.1f)" % unit,
	)


## The mirror places a 2D body's proxy at its centre lifted by half its height: the same lift.
func _mirror(t: TestContext, unit: float) -> void:
	var xf := Transform2D(0.4, Vector2(210.0, 95.0))
	var row := { "offset": Vector2(3.0, -2.0), "size3": Vector3.ONE, "half_height": 18.0 * unit }
	var placed := MirrorProxy.lift(xf, row).origin
	var centre := xf * (row["offset"] as Vector2)
	t.check(
		placed.is_equal_approx(PlanSpace.lift(centre, 18.0)),
		"the mirror's lift is PlanSpace's (x%.1f): %s vs %s" % [
			unit,
			placed,
			PlanSpace.lift(centre, 18.0),
		],
	)


## A 2D body's transform lifts to the 3D one that carries the same local point to the same world
## point: a point 10 px along the body's x and 4 down its y, turned and moved by the 2D transform,
## lands where the twin's transform puts the lifted local point. And `plan_transform` undoes it.
func _transforms(t: TestContext, unit: float) -> void:
	var xf := Transform2D(0.7, Vector2(210.0, 95.0))
	var local := Vector2(10.0, 4.0)
	var world_2d := xf * local
	var lifted := PlanSpace.lift_transform(xf, 12.0)
	var world_3d := lifted * (Vector3(local.x, 0.0, local.y) * unit)
	t.check(
		world_3d.is_equal_approx(PlanSpace.lift(world_2d, 12.0)),
		"a lifted transform puts a local point where the 2D one does (x%.1f): %s vs %s" % [
			unit,
			world_3d,
			PlanSpace.lift(world_2d, 12.0),
		],
	)
	t.check(
		lifted.basis.is_equal_approx(Basis(Vector3.UP, -0.7)),
		"a 2D turn is a turn about up the other way (x%.1f)" % unit,
	)
	var back := PlanSpace.plan_transform(lifted)
	t.check(
		back.origin.is_equal_approx(xf.origin) and is_equal_approx(back.get_rotation(), 0.7),
		"plan_transform undoes lift_transform (x%.1f): %s" % [unit, back],
	)
