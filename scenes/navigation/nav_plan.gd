class_name NavPlan extends RefCounted
## Navigation domain: the plan-space face of `NavigationServer3D` (#194 nav3d-b, D4). A plan point
## `Vector2` (x, y) is the point (x, 0, y) of the nav's 3D floor, on the one plane every mesh is
## baked and held on (`NavSource.bake_polygon`, in px as the plan is, whatever `RenderConfig.unit`
## the render scales by), so a map's answer is lifted in and read back out here and `NavBuilder`'s
## callers keep plan `Vector2`s. Every query of a map goes through these.


## The 3D point of the nav's floor under plan point `p`.
static func lift(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## The plan point of a 3D point of the nav's floor.
static func plan_of(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## `v` read as plan points.
static func plan_path(v: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(v.size())
	for i in v.size():
		out[i] = Vector2(v[i].x, v[i].z)
	return out


## The point of `map`'s navmesh closest to plan point `p`.
static func closest(map: RID, p: Vector2) -> Vector2:
	return plan_of(NavigationServer3D.map_get_closest_point(map, lift(p)))


## The region of `map` that owns the mesh point closest to plan point `p`.
static func owner_at(map: RID, p: Vector2) -> RID:
	return NavigationServer3D.map_get_closest_point_owner(map, lift(p))


## The shortest path over `map` from plan point `from` to `to` as plan points (empty when there is
## none): the corridor's waypoints when `optimize`, else the polygons' centres and edge crossings.
static func path(
	map: RID, from: Vector2, to: Vector2, optimize := true
) -> PackedVector2Array:
	return plan_path(NavigationServer3D.map_get_path(map, lift(from), lift(to), optimize))


## How many times `map` has taken a change in (0 before its first synchronization).
static func iteration(map: RID) -> int:
	return NavigationServer3D.map_get_iteration_id(map)
