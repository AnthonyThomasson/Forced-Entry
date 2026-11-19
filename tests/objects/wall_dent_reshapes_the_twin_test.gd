extends GameTest
## A dent follows into the wall's 3D body (`WallTwin`, interface 29, #194 walls3d): when hits cut a
## wall segment's 2D collider into the convex pieces of its dented outline, the segment's 3D shapes
## are cut again from the same dents, so a ray, a fragment or a lob meets the outline the 2D
## footprint has. Both have the same corners; an untouched segment keeps its one box.

const SHOTS := 8
const TOP := 96.0


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
	for node in t.world.find_children("*", "StaticBody2D", true, false):
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
	t.expect_near(TwinShapes.top_of(twin), TOP, 0.5, "the wall is still 96 px tall")


## The corners (plan px, rounded, sorted) of the 2D colliders of segment `index` of `wall`.
func _corners_2d(wall: Node2D, index: int) -> Array:
	var corners: Array = []
	for holder: CollisionShape2D in wall.segment_shapes().get(index, []):
		if holder.shape is ConvexPolygonShape2D:
			for point in (holder.shape as ConvexPolygonShape2D).points:
				corners.append(_round(holder.transform * point))
		elif holder.shape is RectangleShape2D:
			var half := (holder.shape as RectangleShape2D).size * 0.5
			for sign_x in [-1.0, 1.0]:
				for sign_y in [-1.0, 1.0]:
					corners.append(_round(holder.transform * (half * Vector2(sign_x, sign_y))))
	return _unique(corners)


## The corners (plan px, rounded, sorted) of the shapes of `twin` that lie on segment `index`'s 2D
## colliders' own corners' bounding box: the shapes cut for that segment.
func _corners_3d(twin: Node3D, wall: Node2D, index: int) -> Array:
	var bounds := Rect2()
	var first := true
	for holder: CollisionShape2D in wall.segment_shapes().get(index, []):
		var rect := _plan_box(holder)
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


## The plan rectangle a 2D collider covers.
func _plan_box(holder: CollisionShape2D) -> Rect2:
	if holder.shape is RectangleShape2D:
		var size := (holder.shape as RectangleShape2D).size
		return Rect2(holder.position - size * 0.5, size)
	var points := (holder.shape as ConvexPolygonShape2D).points
	var box := Rect2(holder.transform * points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(holder.transform * point)
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
