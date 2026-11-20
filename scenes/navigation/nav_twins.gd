class_name NavTwins extends RefCounted
## Navigation domain: what a bake reads of the world, taken from the 3D twins (`TwinSpace`,
## interface 29), not from the 2D colliders (ADR 0014): the floor-plan
## polygons the twin of a wall, a piece or a character casts on the floor
## (`TwinShapes.footprint_of`), in world plan space. A bake projects at the plan, never by an
## agent's height, so a doorway's lintel (a header from a door's height to the wall's top, in the
## wall's twin) closes nothing: `footprints` leaves out what hangs over the floor when asked.
## `NavSource` (the walls), `NavHoles`,
## `NavPieces` (the furniture) and `NavBuilder.character_holes` call it.

## How high (px) a shape's underside may be above the floor and still stand on it. A lintel's is a
## door's height, 84 px or more.
const FLOOR_SLACK := 1.0


## The walls under `house`, in the order a walk of its descendants finds them. A wall is a static
## body that reports its segments (Objects' `Wall`, duck-typed): a door is no wall, its leaf leaves
## the bake alone (`NavLeaves`).
static func walls_under(house: Node2D) -> Array:
	var out: Array = []
	for node in house.find_children("*", "StaticBody2D", true, false):
		if node.has_method(&"wall_segments"):
			out.append(node)
	return out


## The twin of `body` when it stands in the twin space's tree, else null (not twinned yet, or no
## domain builds one).
static func twin_of(body: Node) -> Node3D:
	var twin := TwinSpace.twin_for(body)
	return twin if twin != null and twin.is_inside_tree() else null


## The footprint of each shape of `body`'s twin: a convex plan polygon (px, world space) for each,
## in the order the twin holds its shapes. With `grounded`, only the shapes that stand on the floor
## (a wall's lintel is left out). Empty for a body with no twin.
static func footprints(body: Node, grounded := false) -> Array:
	var out: Array = []
	for part: Array in parts(body, grounded):
		var ring := footprint(part[0], part[1])
		if not ring.is_empty():
			out.append(ring)
	return out


## The plan polygon `shape` stands on at `pose` (`TwinShapes.footprint_of`; an upright box, the
## most of a district's shapes, is its four corners without the hull).
static func footprint(shape: Shape3D, pose: Transform3D) -> PackedVector2Array:
	if shape is BoxShape3D and pose.basis.y.is_equal_approx(Vector3.UP):
		var half := (shape as BoxShape3D).size * 0.5
		return PackedVector2Array([
			PlanSpace.plan_of(pose * Vector3(-half.x, 0.0, -half.z)),
			PlanSpace.plan_of(pose * Vector3(half.x, 0.0, -half.z)),
			PlanSpace.plan_of(pose * Vector3(half.x, 0.0, half.z)),
			PlanSpace.plan_of(pose * Vector3(-half.x, 0.0, half.z)),
		])
	return TwinShapes.footprint_of(shape, pose)


## Each shape of `body`'s twin as `[shape, pose]` (`pose` its place in the twin space), in the order
## the twin holds its shapes; with `grounded` only those that stand on the floor.
static func parts(body: Node, grounded := false) -> Array:
	var out: Array = []
	var twin := twin_of(body)
	if twin == null:
		return out
	var at := twin.global_transform
	for child in twin.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		if grounded and base_of(holder) > FLOOR_SLACK:
			continue
		out.append([holder.shape, at * holder.transform])
	return out


## What `body`'s footprint depends on: its twin and the twin's pose, compared to know the footprint
## has to be cut again. `null` when it has no twin.
static func stamp_of(body: Node) -> Variant:
	var twin := twin_of(body)
	if twin == null:
		return null
	return [twin, twin.global_transform]


## The height (px above the floor) of the underside of `holder`'s shape in its twin's frame.
static func base_of(holder: CollisionShape3D) -> float:
	var shape := holder.shape
	var low := 0.0
	if shape is BoxShape3D:
		low = -(shape as BoxShape3D).size.y * 0.5
	elif shape is CylinderShape3D:
		low = -(shape as CylinderShape3D).height * 0.5
	elif shape is CapsuleShape3D:
		low = -(shape as CapsuleShape3D).height * 0.5
	elif shape is ConvexPolygonShape3D:
		low = INF
		for point in (shape as ConvexPolygonShape3D).points:
			low = minf(low, point.y)
	return PlanSpace.height_of(holder.position + Vector3(0.0, low, 0.0))
