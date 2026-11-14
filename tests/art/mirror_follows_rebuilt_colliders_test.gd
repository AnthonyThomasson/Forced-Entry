extends GameTest
## The 3D mirror follows a body whose colliders are rebuilt (#193, Art's `WorldMirror`, interface
## 27). A wall that is hit rebuilds a segment's colliders (the old `CollisionShape2D`s are freed
## and new ones added under the same `StaticBody2D`, `wall.gd`), and a static body is never
## followed frame by frame, so the mirror must notice the change itself: the proxies of the wall
## afterwards are one box for each of its current collision shapes, in the places and sizes those
## shapes have, and none is left for a shape that is gone. Read off the proxies' world boxes and the
## wall's shapes (a hit as `tests/objects/wall_dents_share_a_rebuild_test.gd` lands one).

const SCALE := 0.5
const SHOTS := 5

var _mirror: Node3D


func describe() -> Dictionary:
	return {
		"name": "The 3D mirror re-mirrors a wall whose colliders were rebuilt by a hit",
		"description": "After a wall is dented and its segment colliders are rebuilt, its proxies "
			+ "are one box per current collision shape (place and size) and none is left over.",
		"tags": ["mirror", "3d", "render", "wall"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)
	s.set_static(RenderConfig, &"unit", SCALE)


func run(t: TestContext) -> void:
	var wall: Node = null
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			wall = node
			break
	if not t.require(wall != null, "the arena has a wall"):
		return
	await t.frames(2)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = WorldMirror.new()
	view.add_child(_mirror)
	_mirror.mirror(t.world)
	await t.frames(3)
	var before := _shape_ids(wall)
	t.expect_eq(
		_mirror.proxies_of(wall).size(), before.size(), "premise: a proxy for each wall collider"
	)
	await _hit(t, wall)
	await t.frames(4)
	var after := _shape_ids(wall)
	if not t.require(after != before, "premise: the hits rebuilt the wall's colliders"):
		return
	var proxies: Array = _mirror.proxies_of(wall)
	t.expect_eq(proxies.size(), after.size(), "the wall has a proxy for each current collider")
	t.check(
		proxies.all(func(p): return is_instance_valid(p) and p.is_inside_tree()),
		"and none of them is a freed one's",
	)
	t.expect_eq(_boxes_of_proxies(proxies), _boxes_of_shapes(wall), "in the colliders' places")


## Three volleys of hits along the wall's top, each landing in one frame.
func _hit(t: TestContext, wall: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for volley in 3:
		for k in SHOTS:
			var hit := HitInfo.new()
			hit.position = wall.to_global(Vector2(rng.randf_range(80.0, 520.0), 0.0))
			hit.normal = Vector2.DOWN
			hit.direction = Vector2.UP
			hit.damage = rng.randf_range(10.0, 40.0)
			hit.speed_factor = 1.0
			wall.take_hit(hit)
		await t.frames(2)


## The live collision shapes directly under `wall`: enabled, not on their way out.
func _live_shapes(wall: Node) -> Array:
	return wall.get_children().filter(
		func(c): return (
			c is CollisionShape2D and not c.disabled and c.shape != null
			and not c.is_queued_for_deletion()
		)
	)


## The instance ids of the wall's live shapes, sorted.
func _shape_ids(wall: Node) -> Array:
	var ids: Array = _live_shapes(wall).map(func(c): return c.get_instance_id())
	ids.sort()
	return ids


## Where and how big each live shape is on the ground, in 3D units: the centre and size of its
## points' bounding box (x, z, width, depth), rounded to a tenth, sorted.
func _boxes_of_shapes(wall: Node) -> Array:
	var out: Array = []
	for node: CollisionShape2D in _live_shapes(wall):
		var rect := _bounds(node.shape)
		var centre: Vector2 = node.global_transform * rect.get_center()
		out.append(_key(centre * SCALE, rect.size * SCALE))
	out.sort()
	return out


## The same for the proxies: each one's world box on the ground.
func _boxes_of_proxies(proxies: Array) -> Array:
	var out: Array = []
	for proxy: MeshInstance3D in proxies:
		var box: AABB = proxy.global_transform * proxy.get_aabb()
		var centre := box.get_center()
		out.append(_key(Vector2(centre.x, centre.z), Vector2(box.size.x, box.size.z)))
	out.sort()
	return out


## A comparable key: place and size rounded to a tenth of a unit.
func _key(centre: Vector2, size: Vector2) -> String:
	return "%.1f,%.1f %.1fx%.1f" % [centre.x, centre.y, size.x, size.y]


## The rectangle a rectangle or convex polygon shape covers in its own frame, read off the shape.
func _bounds(shape: Shape2D) -> Rect2:
	if shape is RectangleShape2D:
		return Rect2(-(shape as RectangleShape2D).size * 0.5, (shape as RectangleShape2D).size)
	var points := (shape as ConvexPolygonShape2D).points
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect
