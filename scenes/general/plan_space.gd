class_name PlanSpace
## General domain, the plan-space helper (#194, D4): AI, world generation, `NavBuilder`'s API and
## most tests keep a `Vector2` that means plan space, the floor plan `(x, y)` of the 2D sim, which
## is `(x, z)` on the 3D ground; height enters only where it matters (an eye, a muzzle, a top, a
## grenade's altitude). This lifts a plan point and a height to a `Vector3` and back, on the one
## scale the 3D render and its mirror use (`RenderConfig.unit`: `(x, y)` -> `(x, 0, y) * unit`),
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
