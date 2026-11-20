extends GameTest
## A dent follows into the wall's 3D body (`WallTwin`, interface 29, #194 walls3d): when hits cut a
## wall segment's 2D collider into the convex pieces of its dented outline, the segment's 3D shapes
## are cut again from the same dents, so a ray, a fragment or a lob meets the outline the 2D
## footprint has. Both have the same corners; an untouched segment keeps its one box.

const SHOTS := 8
const TOP := 96.0
## The room-side face of the arena's top wall as built (the wall is 12 px thick about y = 0).
const BUILT_FACE := 6.0


func describe() -> Dictionary:
	return {
		"name": "A dent on a wall reshapes its 3D body with its 2D collider",
		"description": "Hits that dent one segment of the arena's wall leave its 3D shapes with "
			+ "the corners of its 2D collider pieces, 96 px tall; another segment keeps its box.",
		"tags": ["walls", "twins", "deformation", "3d"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var wall: Node2D = null
	for node in NavTwins.walls_under(t.world):
		if node.has_method("wall_segments"):
			wall = node
			break
	if not t.require(wall != null, "premise: the arena has a wall"):
		return
	var twin := TwinSpace.twin_for(wall)
	if not t.require(twin != null, "premise: the wall has a 3D body"):
		return
	var before := _corners_2d(wall, 0)
	for k in SHOTS:
		var hit := HitInfo.new()
		hit.position = wall.to_global(Vector2(200.0 + k * 12.0, 0.0))
		hit.normal = Vector2.DOWN
		hit.direction = Vector2.UP
		hit.damage = 40.0
		hit.speed_factor = 1.0
		wall.take_hit(hit)
	await t.frames(4)
	var after := _corners_2d(wall, 0)
	t.check(after != before, "premise: the hits cut the segment's collider")
	t.check(
		_corners_3d(twin, wall, 0) == after,
		"the 3D shapes have the corners of the 2D pieces (%s vs %s)" % [
			_corners_3d(twin, wall, 0), after,
		],
	)
	t.check(_corners_3d(twin, wall, 1) == _corners_2d(wall, 1), "another segment is as built")
	_ray_meets_the_new_face(t, wall)
	t.expect_near(TwinShapes.top_of(twin), TOP, 0.5, "the wall is still 96 px tall")


## A level ray at 48 px from the room into the deepest dent strikes the dented face the 2D pieces
## have there, not the face the wall was built with.
func _ray_meets_the_new_face(t: TestContext, wall: Node2D) -> void:
	var polygons := _polygons_2d(wall, 0)
	var best_x := 0.0
	var best := 0.0
	for k in 340:
		var x := 150.0 + k * 0.5
		var recess := BUILT_FACE - _face_y(polygons, x)
		if recess > best:
			best = recess
			best_x = x
	if not t.require(best >= 1.0, "premise: the hits dented the face in (%.1f px)" % best):
		return
	var from := PlanSpace.lift(wall.to_global(Vector2(best_x, 20.0)), 48.0)
	var to := PlanSpace.lift(wall.to_global(Vector2(best_x, -20.0)), 48.0)
	var hit: Dictionary = t.world.twin_space().space().intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.TWIN_WORLD)
	)
	if not t.require(not hit.is_empty(), "the ray strikes the wall at x %.1f" % best_x):
		return
	var struck := wall.to_local(PlanSpace.plan_of(hit["position"])).y
	t.expect_near(struck, BUILT_FACE - best, 0.4, "it strikes the dented face, not the built one")


## The y (the wall's frame) of the room-side face of `polygons` at `x`: the first inside point
## walking in from the built face; the built face's own y for none.
func _face_y(polygons: Array, x: float) -> float:
	var y := BUILT_FACE
	while y > -BUILT_FACE:
		for polygon: PackedVector2Array in polygons:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				return y
		y -= 0.1
	return BUILT_FACE


## The outlines (the wall's frame) of segment `index` of `wall`.
func _polygons_2d(wall: Node2D, index: int) -> Array:
	var out: Array = []
	for outline: PackedVector2Array in wall.segment_shapes().get(index, []):
		out.append(outline)
	return out


## The corners (plan px, rounded, sorted) of the outlines of segment `index` of `wall`.
func _corners_2d(wall: Node2D, index: int) -> Array:
	var corners: Array = []
	for outline: PackedVector2Array in wall.segment_shapes().get(index, []):
		for point in outline:
			corners.append(_round(point))
	return _unique(corners)


## The corners (plan px, rounded, sorted) of the shapes of `twin` that lie on segment `index`'s 2D
## colliders' own corners' bounding box: the shapes cut for that segment.
func _corners_3d(twin: Node3D, wall: Node2D, index: int) -> Array:
	var bounds := Rect2()
	var first := true
	for outline: PackedVector2Array in wall.segment_shapes().get(index, []):
		var rect := _plan_box(outline)
		bounds = rect if first else bounds.merge(rect)
		first = false
	bounds = bounds.grow(0.6)
	var corners: Array = []
	for child in twin.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		var points: Array = []
		if holder.shape is BoxShape3D:
			var half := (holder.shape as BoxShape3D).size * 0.5
			for sign_x in [-1.0, 1.0]:
				for sign_z in [-1.0, 1.0]:
					points.append(holder.transform * Vector3(half.x * sign_x, 0.0, half.z * sign_z))
		elif holder.shape is ConvexPolygonShape3D:
			for point in (holder.shape as ConvexPolygonShape3D).points:
				points.append(holder.transform * point)
		var plan: Array = points.map(func(p: Vector3) -> Vector2: return PlanSpace.plan_of(p))
		if plan.all(func(p: Vector2) -> bool: return bounds.has_point(p)):
			corners.append_array(plan.map(_round))
	return _unique(corners)


## The plan rectangle an outline covers.
func _plan_box(outline: PackedVector2Array) -> Rect2:
	var box := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		box = box.expand(point)
	return box


func _round(point: Vector2) -> Vector2:
	return (point * 2.0).round() / 2.0


## `points` without repeats, in order.
func _unique(points: Array) -> Array:
	var out: Array = []
	for point in points:
		if not out.has(point):
			out.append(point)
	out.sort_custom(
		func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return out
