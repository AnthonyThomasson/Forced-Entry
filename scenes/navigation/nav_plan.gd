class_name NavPlan extends RefCounted
## Navigation domain: the plan-space face of `NavigationServer3D` (D4). A plan point
## `Vector2` (x, y) is the point (x, 0, y) of the nav's 3D floor, on the one plane every mesh is
## baked and held on (`NavSource.bake_polygon`, in px as the plan is, whatever `RenderConfig.unit`
## the render scales by), so a map's answer is lifted in and read back out here and `NavBuilder`'s
## callers keep plan `Vector2`s. Every query of a map goes through these.

## The meta a region carries: the plan-space polygon its mesh was made from (`assign`).
const POLYGON_META := &"nav_polygon"


## The 3D point of the nav's floor under plan point `p`.
static func lift(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


## The plan point of a 3D point of the nav's floor.
static func plan_of(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The plan point `p`, a point in `node`'s frame (a region's: its vertices'), in the world's.
static func global_of(node: Node3D, p: Vector2) -> Vector2:
	return plan_of(node.to_global(lift(p)))


## The plan point `p` of the world, as a point in `node`'s frame.
static func local_of(node: Node3D, p: Vector2) -> Vector2:
	return plan_of(node.to_local(lift(p)))


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


## Give `region` the navmesh of `poly` (a plan-space polygon: vertices (x, y) in the region's
## frame, as the bake leaves them): vertices lifted to (x, 0, y), on the cell size and height of
## the maps. The polygon stays on the region (`polygon_of`) for what reads a region's plan geometry
## (`NavSeams`, `NavTiles.probe_of`). A new mesh each time, so the server takes it in afresh.
## `mesh` is `mesh_of(poly)` when the caller made it already (a bake's worker thread did, so the
## landing frame is only the assignment); null makes it here.
static func assign(
	region: NavigationRegion3D, poly: NavigationPolygon, mesh: NavigationMesh = null
) -> void:
	region.set_meta(POLYGON_META, poly)
	region.navigation_mesh = mesh if mesh != null else mesh_of(poly)


## The plan-space polygon last `assign`ed to `region`; null before one.
static func polygon_of(region: NavigationRegion3D) -> NavigationPolygon:
	if not region.has_meta(POLYGON_META):
		return null
	return region.get_meta(POLYGON_META) as NavigationPolygon


## The 3D navmesh of `poly`.
static func mesh_of(poly: NavigationPolygon) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = NavSource.CELL_SIZE
	mesh.cell_height = NavSource.CELL_HEIGHT
	var vertices := PackedVector3Array()
	var plan := poly.vertices
	vertices.resize(plan.size())
	for i in plan.size():
		vertices[i] = Vector3(plan[i].x, 0.0, plan[i].y)
	mesh.vertices = vertices
	for i in poly.get_polygon_count():
		mesh.add_polygon(poly.get_polygon(i))
	return mesh
