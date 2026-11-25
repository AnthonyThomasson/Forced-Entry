extends RefCounted
## FROZEN COPY of `TwinShapes.footprint_of` as it was before the cheaper build (#194 fixes3): the
## oracle `general/twin_footprint_matches_frozen` compares the live one to it bit for bit over every
## twin of a real district. Change it never; change the live one only while this test holds.

const ROUND_SIDES := 16


## The floor-plan polygon (px, plan space, convex, no repeated point) that `shape`, placed at `at`
## in the twin space, casts on the floor: the hull of its extreme points moved to plan. A box is its
## rectangle, an upright cylinder a `ROUND_SIDES`-sided disc, a convex hull its points' hull, and a
## tilted one the hull of what it reaches. Empty for a shape with no extent (a plane, a concave
## mesh). What the navigation bake and the player's view read of a twin.
static func footprint_of(shape: Shape3D, at: Transform3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _extremes(shape):
		points.append(PlanSpace.plan_of(at * point))
	if points.size() < 3:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)  # the engine closes the ring
	return hull if hull.size() >= 3 else PackedVector2Array()


## The points of `shape` (its own frame, 3D units) whose hull is the shape's extent.
static func _extremes(shape: Shape3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append(Vector3(half.x * sx, half.y * sy, half.z * sz))
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		_ring(out, cylinder.radius, cylinder.height * 0.5)
		_ring(out, cylinder.radius, -cylinder.height * 0.5)
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var straight := capsule.height * 0.5 - capsule.radius
		_ring(out, capsule.radius, straight)
		_ring(out, capsule.radius, -straight)
		out.append(Vector3(0.0, capsule.height * 0.5, 0.0))
		out.append(Vector3(0.0, -capsule.height * 0.5, 0.0))
	elif shape is SphereShape3D:
		_ring(out, (shape as SphereShape3D).radius, 0.0)
	elif shape is ConvexPolygonShape3D:
		out = (shape as ConvexPolygonShape3D).points
	return out


## Add to `out` the `ROUND_SIDES` points of the circle of `radius` round the up axis, `y` up.
static func _ring(out: PackedVector3Array, radius: float, y: float) -> void:
	for i in ROUND_SIDES:
		var angle := float(i) / ROUND_SIDES * TAU
		out.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
