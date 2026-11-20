extends GameTest
## The static classes carry their meshes (#194 del2d-b2, interface 27 and 29): where a body has a
## twin that is a static body (a wall, a floor, an anchored or wall-hung piece), the 3D view's mesh
## is a child of that twin, with no transform of its own, so the picture is where the twin is and
## the mirror writes nothing for it. A world no view looks at builds no mesh at all. The mirror
## keeps the shown rules (a hidden body, a disabled shape) and `remirror` for a carried mesh, and
## says `built` for it, as the wall fade listens to.

const POST := {
	"name": "Post", "shape": "circle", "size": Vector2(14, 14), "color": Color(0.34, 0.33, 0.27),
	"material": "metal", "weight": 250, "penetration": 85, "anchored": true,
	"art": "streetlight", "art_opts": { "head": "cobra" },
}
const POST_AT := Vector2(300, 200)
const LATER_AT := Vector2(500, 200)


func describe() -> Dictionary:
	return {
		"name": "A static twin carries its mesh",
		"description": "With a view, a wall, a floor and an anchored piece have their mesh as a "
			+ "child of their twin (identity transform, `mesh_of` finds it, `built` was said); "
			+ "one spawned later too; the shown rules and remirror still work; a world with no "
			+ "view builds no mesh; the mesh goes with the twin.",
		"tags": ["mirror", "render3d", "twins", "3d", "walls", "floors", "carriers"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.object(&"post", POST, POST_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var twins := TwinSpace.of_world(t.world)
	if not t.require(twins != null, "premise: the world has a twin space"):
		return
	await t.frames(3)
	var post := t.object(&"post")
	var wall := _first_wall(t.world)
	var floor_node := _first_floor(t.world)
	if not t.require(
		wall != null and floor_node != null,
		"premise: the arena has a wall and floor",
	):
		return
	_check_viewless(t, twins, [post, wall, floor_node])
	await _check_other_world(t, post, floor_node)
	var mirror := _view(t)
	var built: Array[Node] = []
	mirror.built.connect(func(body: Node, _mesh: Node3D) -> void: built.append(body))
	mirror.mirror(t.world)
	await t.frames(3)
	_check_carried(t, mirror, post, "the anchored piece")
	_check_carried(t, mirror, wall, "the wall")
	_check_carried(t, mirror, floor_node, "the floor")
	t.check(built.has(post) and built.has(wall), "`built` was said for a carried piece and wall")
	await _check_spawned_later(t, mirror)
	await _check_shown_rules(t, mirror, post)
	await _check_remirror(t, mirror, post)
	await _check_goes_with_twin(t, mirror)
	await _check_mirrored_twice(t, mirror, floor_node, wall)


func _first_wall(world: Node) -> Node:
	for body: Node in world.find_children("*", "StaticBody2D", true, false):
		if body.has_method(&"segment_shapes"):
			return body
	return null


func _first_floor(world: Node) -> Node:
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node):
			return node
	return null


func _view(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()  # drawn in the twins' world
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	ObjectMeshes.register(mirror.builders)
	view.add_child(mirror)
	return mirror


## No view, no mesh: a twin is its shapes and nothing drawn.
func _check_viewless(t: TestContext, twins: TwinSpace, bodies: Array) -> void:
	for body: Node in bodies:
		var twin := twins.twin_of(body)
		if not t.require(twin != null, "premise: %s has a twin" % body.name):
			continue
		t.check(
			twin.find_children("*", "MeshInstance3D", true, false).is_empty(),
			"with no view %s's twin carries no mesh" % body.name,
		)


func _check_carried(t: TestContext, mirror: WorldMirror, body: Node, what: String) -> void:
	var twin := TwinSpace.twin_for(body)
	var mesh := mirror.mesh_of(body)
	if not t.require(mesh != null and twin != null, "premise: %s has a mesh and a twin" % what):
		return
	t.check(mesh.get_parent() == twin, "%s's mesh is a child of its twin" % what)
	t.check(
		mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"carried with no transform of its own",
	)
	t.check(mesh.is_inside_tree(), "%s's mesh is in the tree" % what)


func _check_spawned_later(t: TestContext, mirror: WorldMirror) -> void:
	var later := ObjectFactory.spawn(POST, LATER_AT, t.world)
	await t.frames(4)
	_check_carried(t, mirror, later, "a post spawned after the view began")
	t.check(
		mirror.mesh_of(later).global_position.distance_to(PlanSpace.lift(LATER_AT)) < 0.01,
		"at the place its body was put",
	)
	later.queue_free()
	await t.frames(3)


func _check_shown_rules(t: TestContext, mirror: WorldMirror, post: Node2D) -> void:
	var mesh := mirror.mesh_of(post)
	t.check(mesh.visible, "a carried mesh shows")
	post.visible = false
	await t.frames(2)
	t.check(not mesh.visible, "it is hidden while its body's own visible is off")
	post.visible = true
	await t.frames(2)
	t.check(mesh.visible, "and shown again")


func _check_remirror(t: TestContext, mirror: WorldMirror, post: Node2D) -> void:
	var old := mirror.mesh_of(post)
	mirror.remirror(post)
	var fresh := mirror.mesh_of(post)
	t.check(fresh != null and fresh != old, "remirror builds the mesh again")
	t.check(fresh != null and fresh.get_parent() == TwinSpace.twin_for(post), "still on its twin")
	await t.frames(2)
	t.check(not is_instance_valid(old) or old.is_queued_for_deletion(), "the old mesh is freed")
	t.check(mirror.proxies_of(post).size() == 1, "and the piece has one mesh")


func _check_goes_with_twin(t: TestContext, mirror: WorldMirror) -> void:
	var gone := ObjectFactory.spawn(POST, LATER_AT, t.world)
	await t.frames(4)
	var mesh := mirror.mesh_of(gone)
	if not t.require(mesh != null, "premise: a second post is carried"):
		return
	var before := mirror.count
	gone.queue_free()
	await t.frames(4)
	t.check(not is_instance_valid(mesh) or mesh.is_queued_for_deletion(), "the mesh goes with it")
	t.check(mirror.count == before - 1, "and is no longer counted")


## A mirror drawn in a world of its own is not in the twins' world: it follows its bodies by meshes
## of its own, and nothing is put on the twins.
func _check_other_world(t: TestContext, post: Node, floor_node: Node) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	ObjectMeshes.register(mirror.builders)
	view.add_child(mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	for body: Node in [post, floor_node]:
		var mesh := mirror.mesh_of(body)
		if not t.require(mesh != null, "premise: %s is meshed in its own world" % body.name):
			continue
		t.check(
			mesh.get_parent() == mirror,
			"a mirror in another world keeps %s's mesh" % body.name,
		)
		t.check(
			TwinSpace.twin_for(body).find_children("*", "MeshInstance3D", true, false).is_empty(),
			"and puts nothing on the twin of %s" % body.name,
		)
	view.queue_free()
	await t.frames(2)


## Mirroring the world again shows each static body once: its old mesh goes.
func _check_mirrored_twice(
	t: TestContext, mirror: WorldMirror, floor_node: Node, wall: Node
) -> void:
	var before := mirror.count
	var kids := [TwinSpace.twin_for(floor_node).get_child_count()]
	kids.append(TwinSpace.twin_for(wall).get_child_count())
	mirror.mirror(t.world)
	await t.frames(3)
	t.expect_eq(mirror.count, before, "mirroring again counts each body once")
	t.expect_eq(TwinSpace.twin_for(floor_node).get_child_count(), kids[0], "a floor has one mesh")
	t.expect_eq(TwinSpace.twin_for(wall).get_child_count(), kids[1], "a wall has one mesh")
