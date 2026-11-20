extends GameTest
## Art's `MeshFollower` (#194 del2d-b3b): the small follower for drawn things that are no physics
## body (a floor stencil, a dropped item, a thrown grenade: Node2Ds in a tracked group), which no
## twin carries a mesh for. The same `track` / `track_group` API the mirror had, the same rules: a
## tracked node's mesh stands where the node is and turns with it, written only when the node's
## transform changed, hidden with the node, freed with it (parked while it is reparented), taken up
## as it joins its group, built again by `remirror`. A group's node that a builder gives no mesh is
## not asked again until `remirror`.

const A_AT := Vector2(300, 100)
const B_AT := Vector2(340, 130)


func describe() -> Dictionary:
	return {
		"name": "The mesh follower shows what has no body: follows, hides, frees with it",
		"description": "A tracked node's mesh stands on it, turns with it, is written only when "
			+ "it moved, hidden and shown with it, parked while it is out of the tree and freed "
			+ "with it; a group takes the nodes there and those that join; remirror builds a "
			+ "mesh again; a builder's null is not asked again.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	await t.frames(3)
	var follower := _follower(t)
	await _check_track(t, follower)
	await _check_group(t, follower)
	await _check_parked(t, follower)
	await _check_remirror(t, follower)
	await _check_null_builder(t, follower)
	await _check_group_before_follow(t)
	await _check_left_out(t, follower)


func _follower(t: TestContext) -> MeshFollower:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var follower := MeshFollower.new()
	view.add_child(follower)
	follower.follow(t.world)
	return follower


func _named(label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.set_meta(&"label", label)
	return node


func _node(t: TestContext, at: Vector2) -> Node2D:
	var node := Node2D.new()
	t.world.add_child(node)
	node.global_position = at
	return node


func _check_track(t: TestContext, follower: MeshFollower) -> void:
	var item := _node(t, A_AT)
	var shown := follower.track(item, func(_n: Node2D) -> Node3D: return _named("ItemMesh"))
	if not t.require(shown != null and follower.count == 1, "a tracked node has one mesh"):
		return
	t.check(shown.get_parent() == follower, "the mesh is the follower's child")
	t.check(follower.mesh_of(item) == shown, "mesh_of finds it")
	await t.frames(2)
	t.expect_near(shown.global_position.x, A_AT.x, 0.01, "the mesh stands on the node (x)")
	t.expect_near(shown.global_position.z, A_AT.y, 0.01, "the mesh stands on the node (z)")
	item.global_position = B_AT
	item.rotation = 0.5
	await t.frames(2)
	t.expect_near(shown.global_position.x, B_AT.x, 0.01, "it follows the node (x)")
	t.expect_near(shown.global_position.z, B_AT.y, 0.01, "it follows the node (z)")
	t.expect_near(shown.rotation.y, -0.5, 0.01, "it turns with the node (a 2D turn is -angle)")
	await t.frames(2)
	follower.update()
	t.expect_eq(follower.written, 0, "a still node is not written")
	t.expect_eq(follower.followed, 1, "but it is read")
	item.visible = false
	await t.frames(2)
	t.check(not shown.visible, "a hidden node hides its mesh")
	item.visible = true
	await t.frames(2)
	t.check(shown.visible, "and shows it again")
	item.queue_free()
	await t.frames(3)
	t.check(follower.count == 0 and not is_instance_valid(shown), "a freed node's mesh is freed")


func _check_group(t: TestContext, follower: MeshFollower) -> void:
	var early := _node(t, Vector2(100, 100))
	early.add_to_group(&"follow_probe")
	follower.track_group(&"follow_probe", func(_n: Node2D) -> Node3D: return _named("GroupMesh"))
	var late := Node2D.new()
	late.add_to_group(&"follow_probe")
	t.world.add_child(late)
	late.global_position = Vector2(200, 150)
	await t.frames(3)
	for node: Node2D in [early, late]:
		var mesh := follower.mesh_of(node)
		if t.require(
			mesh != null and mesh.get_meta(&"label", "") == "GroupMesh",
			"a group's node is tracked",
		):
			t.expect_near(mesh.global_position.x, node.global_position.x, 0.01, "and stands on it")
	t.expect_eq(follower.count, 2, "two meshes")
	early.queue_free()
	late.queue_free()
	await t.frames(3)
	t.expect_eq(follower.count, 0, "they go with their nodes")


## A tracked node that leaves the tree is parked (hidden, not followed); back in it, it shows where
## it now is.
func _check_parked(t: TestContext, follower: MeshFollower) -> void:
	var item := _node(t, A_AT)
	var shown := follower.track(item, func(_n: Node2D) -> Node3D: return _named("Parked"))
	await t.frames(2)
	t.world.remove_child(item)
	await t.frames(2)
	t.check(is_instance_valid(shown) and not shown.visible, "a node out of the tree is parked")
	t.world.add_child(item)
	item.global_position = B_AT
	await t.frames(3)
	t.check(shown.visible, "it shows again when the node is back")
	t.expect_near(shown.global_position.x, B_AT.x, 0.01, "where the node now is")
	item.queue_free()
	await t.frames(3)
	t.check(not is_instance_valid(shown), "and goes when the node is freed")


func _check_remirror(t: TestContext, follower: MeshFollower) -> void:
	var item := _node(t, A_AT)
	var made: Array[int] = [0]
	var builder := func(_n: Node2D) -> Node3D:
		made[0] += 1
		return _named("Made%d" % made[0])
	var first := follower.track(item, builder)
	follower.remirror(item)
	await t.frames(2)
	var now := follower.mesh_of(item)
	t.check(
		now != null and now != first and now.get_meta(&"label") == "Made2",
		"remirror builds it again",
	)
	t.check(not is_instance_valid(first) or first.is_queued_for_deletion(), "the old one is freed")
	t.expect_eq(follower.count, 1, "still one mesh")
	item.queue_free()
	await t.frames(3)


func _check_null_builder(t: TestContext, follower: MeshFollower) -> void:
	var asked: Array[int] = [0]
	follower.track_group(&"follow_null", func(_n: Node2D) -> Node3D:
		asked[0] += 1
		return null
	)
	var item := _node(t, A_AT)
	item.add_to_group(&"follow_null")
	await t.frames(4)
	t.expect_eq(asked[0], 1, "a builder that gives none is asked once")
	t.check(follower.mesh_of(item) == null, "and the node is not shown")
	item.queue_free()
	await t.frames(2)


## A group tracked before `follow` takes up what is already in the world.
func _check_group_before_follow(t: TestContext) -> void:
	var there := _node(t, Vector2(60, 60))
	there.add_to_group(&"follow_before")
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var follower := MeshFollower.new()
	view.add_child(follower)
	follower.track_group(&"follow_before", func(_n: Node2D) -> Node3D: return _named("Early"))
	follower.follow(t.world)
	await t.frames(3)
	var mesh := follower.mesh_of(there)
	t.check(
		mesh != null and mesh.get_meta(&"label") == "Early",
		"a node already in the group is tracked",
	)
	there.queue_free()


## A subtree the view leaves out loses its meshes at once and shows nothing that joins it later; the
## rest of the world is still shown.
func _check_left_out(t: TestContext, follower: MeshFollower) -> void:
	var gone := Node2D.new()
	t.world.add_child(gone)
	var inside := Node2D.new()
	inside.add_to_group(&"follow_out")
	gone.add_child(inside)
	var beside := _node(t, A_AT)
	beside.add_to_group(&"follow_out")
	follower.track_group(&"follow_out", func(_n: Node2D) -> Node3D: return _named("Out"))
	await t.frames(3)
	t.check(follower.mesh_of(inside) != null and follower.mesh_of(beside) != null, "premise: both")
	follower.leave_out(gone)
	t.check(follower.mesh_of(inside) == null, "a node under the left-out subtree loses its mesh")
	t.check(follower.mesh_of(beside) != null, "the rest is still shown")
	var later := Node2D.new()
	later.add_to_group(&"follow_out")
	gone.add_child(later)
	await t.frames(3)
	t.check(follower.mesh_of(later) == null, "and nothing that joins it later is shown")
	beside.queue_free()
	gone.queue_free()
	await t.frames(2)
