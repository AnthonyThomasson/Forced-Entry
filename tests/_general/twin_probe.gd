extends RefCounted
## Helper of the twin-space tests (`TwinSpace`, interface 29): casts 3D rays into a test world's
## twin space and reads what they hit. A height is px above the floor; a plan point is the 2D
## sim's `(x, y)`.


## The world's twin space (`TwinSpace`).
static func twins(t: TestContext) -> TwinSpace:
	return t.world.twin_space()


## The ray from `from` to `to` (3D points) through the twin space, on `mask`: the hit's `position`,
## `collider` and `owner` (the 2D body the collider stands for), {} when it hits nothing.
static func ray(
	t: TestContext,
	from: Vector3,
	to: Vector3,
	mask: int = PhysicsLayers.TWIN_ALL,
) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := twins(t).space().intersect_ray(query)
	if not hit.is_empty():
		hit["owner"] = TwinSpace.owner_of(hit["collider"])
	return hit


## The ray dropped straight down onto plan point `at` from 300 px up.
static func down(t: TestContext, at: Vector2, mask: int = PhysicsLayers.TWIN_ALL) -> Dictionary:
	return ray(t, PlanSpace.lift(at, 300.0), PlanSpace.lift(at, -50.0), mask)


## How high (px) the ray dropped onto `at` lands, -1000 when it lands on nothing.
static func top_at(t: TestContext, at: Vector2, mask: int = PhysicsLayers.TWIN_ALL) -> float:
	var hit := down(t, at, mask)
	return PlanSpace.height_of(hit["position"]) if not hit.is_empty() else -1000.0


## The ray flown level at `height` px from plan point `from` to plan point `to`.
static func level(
	t: TestContext,
	from: Vector2,
	to: Vector2,
	height: float,
	mask: int = PhysicsLayers.TWIN_ALL,
) -> Dictionary:
	return ray(t, PlanSpace.lift(from, height), PlanSpace.lift(to, height), mask)
