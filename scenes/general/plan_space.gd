class_name PlanSpace
## General domain, the plan-space helper (D4, `docs/adr/0014-twin-staging-and-plan-space.md`): AI,
## world generation, `NavBuilder`'s API and most tests keep a `Vector2` that means plan space, the
## floor plan `(x, y)` of the 2D sim, which is `(x, z)` on the 3D ground; height enters only where
## it matters (an eye, a muzzle, a top, a grenade's altitude). This lifts a plan point and a height
## to a `Vector3` and back, on the one scale the 3D render and its mirror use (`RenderConfig.unit`:
## `(x, y)` -> `(x, 0, y) * unit`),
## so a domain never writes that mapping by hand. Heights are px (`BodyHeights`, `PieceHeights`).


## The 3D point over plan point `plan`, `height` px above the floor: `(x, height, y) * unit`.
static func lift(plan: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(plan.x, height, plan.y) * RenderConfig.unit


## The plan point under 3D point `point`: `(x, z) / unit`.
static func plan_of(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / RenderConfig.unit


## How high (px) 3D point `point` is above the floor: `y / unit`.
static func height_of(point: Vector3) -> float:
	return point.y / RenderConfig.unit


## The 3D transform of a body whose 2D transform is `xf`, `height` px up: its origin lifted
## (`lift`), turned about up by the 2D turn the other way (a 2D turn clockwise on a y-down screen
## is a turn of `-angle` about +y). A local point `(x, y)` of the 2D body is the local 3D point
## `(x, 0, y) * unit` of the lifted one, so the shapes of a body keep their offsets. Scale and skew
## are not carried (a body's shapes carry their own sizes).
static func lift_transform(xf: Transform2D, height: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -xf.get_rotation()), lift(xf.origin, height))


## The 2D transform under 3D transform `xf3` (the other way of `lift_transform`): its origin's
## plan point and its turn about up, ignoring any tilt.
static func plan_transform(xf3: Transform3D) -> Transform2D:
	var along := xf3.basis.x
	return Transform2D(atan2(along.z, along.x), plan_of(xf3.origin))
