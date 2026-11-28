extends GameTest
## A free piece's 2D footprint takes the heading of its 3D body by the twist of its rotation about
## up (`TwinSpace.plan_transform`). A piece turned over about a horizontal axis (a wardrobe on its
## back, 180 degrees) has no twist: the quaternion's up and scalar parts both vanish and the angle
## is noise, so the footprint's rotation, and the art, blood and decals on it, would jump every
## frame (#194). The footprint then holds the heading it had.


func describe() -> Dictionary:
	return {
		"name": "A piece flipped over about a horizontal axis holds the heading of its footprint",
		"description": "A pose turned 180 degrees about x gives the held rotation, however its "
			+ "noise leans; a pose with a heading gives that heading, and a lying one keeps it.",
		"tags": ["twins", "3d", "tipping"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var at := Vector3(40.0, 30.0, 70.0)
	var turned := Basis(Vector3.UP, 0.7)
	t.expect_eq(
		snappedf(TwinSpace.plan_transform(Transform3D(turned, at), 0.0).get_rotation(), 0.001),
		snappedf(-0.7, 0.001),
		"a pose with a heading gives it (the plan's sign)",
	)
	var lying := Basis(Vector3.RIGHT, deg_to_rad(90.0)) * turned
	t.check(
		absf(TwinSpace.plan_transform(Transform3D(lying, at), 0.0).get_rotation() + 0.7) < 0.02,
		"a piece lying on its side keeps the heading it fell with",
	)
	for noise in [0.0, 1.0e-4, -1.0e-4, 3.0e-4]:
		var flipped := Basis(Vector3.UP, noise) * Basis(Vector3.RIGHT, PI)
		var held := 1.234
		var got := TwinSpace.plan_transform(Transform3D(flipped, at), held)
		t.check(
			absf(got.get_rotation() - held) < 1.0e-5,
			"flipped over (noise %s): the heading is held (%.5f)" % [noise, got.get_rotation()],
		)
		t.check(
			got.origin.is_equal_approx(PlanSpace.plan_of(at)),
			"and the origin is where the body is",
		)
