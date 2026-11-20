extends GameTest
## The carried wall mesh follows a wall whose colliders are rebuilt (#193, Art's `MeshCarrier`,
## interface 27). A wall that is hit rebuilds a segment's colliders (the old `CollisionShape2D`s are
## freed and new ones added under the same `StaticBody2D`, `wall.gd`), and the wall's mesh says
## `follows_shapes() -> true` (it replaces the one segment that changed itself): so the carrier
## leaves it be, one mesh on the wall's twin, the same instance before and after, never built again
## (`built` is said once). A wall hit as `tests/objects/wall_dents_share_a_rebuild_test.gd` lands
## one.

const SHOTS := 5

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "The carried wall mesh survives a wall whose colliders were rebuilt by a hit",
		"description": "After a wall is dented and its segment colliders are rebuilt, it still has "
			+ "its one mesh on its twin, the same instance, never built again.",
		"tags": ["mirror", "3d", "render", "wall"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


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
	_mirror = MeshCarrier.new()
	StructureMeshes.register(_mirror.builders)
	var built: Array[Node] = []
	_mirror.built.connect(func(body: Node, _mesh: Node3D) -> void: built.append(body))
	view.add_child(_mirror)
	_mirror.carry(t.world)
	await t.frames(3)
	var before := _shape_ids(wall)
	var mesh := _mirror.mesh_of(wall)
	if not t.require(mesh != null, "premise: the wall has a mesh"):
		return
	t.check(mesh.get_parent() == TwinSpace.twin_for(wall), "premise: it stands on the wall's twin")
	t.check(mesh.has_method(&"follows_shapes"), "premise: it follows the wall's shapes itself")
	await _hit(t, wall)
	await t.frames(4)
	if not t.require(_shape_ids(wall) != before, "premise: the hits rebuilt the wall's colliders"):
		return
	t.check(_mirror.mesh_of(wall) == mesh, "the wall keeps the same mesh")
	t.expect_eq(_mirror.proxies_of(wall).size(), 1, "and has one mesh")
	t.expect_eq(built.count(wall), 1, "the carrier built it once")
	t.check(is_instance_valid(mesh) and mesh.is_inside_tree(), "and it is in the tree")


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
