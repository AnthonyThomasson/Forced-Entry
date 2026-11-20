extends GameTest
## The mesh hook (#193, interface 27): a domain registers a builder with the carrier for a kind
## (`MeshKinds.FURNITURE`) or for a finer key (`MeshKinds.furniture_key("table")`, the `ObjectArt`
## id: the finer key wins, the kind answers the rest), for the floors (`MeshKinds.FLOOR` or
## `floor_key(art)`), and with the follower for a drawn thing that is not a physics body
## (`track(node, builder)`, `track_group(group, builder)`: a dropped item, a bullet) that it follows
## by the rules of a body: written only when its transform changed, hidden with its node, freed when
## it leaves the tree. A body no builder answers is shown by nothing.

const WallProbe := preload("res://tests/_art/art_wall_probe.gd")
const TABLE_AT := Vector2(260, 180)
const CHAIR_AT := Vector2(520, 300)


func describe() -> Dictionary:
	return {
		"name": "The mesh hook takes a finer key, the floors and nodes that are not bodies",
		"description": "A builder for a table's own key wins over the furniture kind's; a floor "
			+ "builder places the floor's own mesh at its corner; a tracked node follows, is "
			+ "hidden and freed with its node and is written only when it moved; a group "
			+ "tracks nodes that join later.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "table", TABLE_AT)
	s.object(&"chair", "armchair", CHAIR_AT)
	s.actor(&"a", &"puppet", Vector2(120, 400))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	mirror.builders[&"furniture:table"] = func(_body: Node2D) -> Node3D: return _named("TableMesh")
	mirror.builders[MeshKinds.FURNITURE] = func(_body: Node2D) -> Node3D:
		return _named("KindMesh")
	mirror.builders[MeshKinds.FLOOR] = func(_floor: Node2D) -> Node3D: return _named("FloorMesh")
	mirror.carry(t.world)
	await t.frames(3)
	_check_keys(t, mirror)
	_check_floor(t, mirror)
	var follower := _follower(t)
	follower.follow(t.world)
	await _check_track(t, follower)
	await _check_group(t, follower)
	await _check_group_before_follow(t)
	await _check_key_is_for_furniture(t)


func _mirror(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	return mirror


func _follower(t: TestContext) -> MeshFollower:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var follower := MeshFollower.new()
	view.add_child(follower)
	return follower


## What shows `node` by a follower: its one mesh, or nothing.
func _meshes(follower: MeshFollower, node: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var mesh := follower.mesh_of(node)
	if mesh != null:
		out.append(mesh)
	return out


func _label(node: Node) -> String:
	return node.get_meta(&"label", "")


func _named(label: String) -> Node3D:
	var node := Node3D.new()
	node.set_meta(&"label", label)  # a name would be changed when two siblings share it
	return node


## The table is shown by its own key's mesh, the armchair by the kind's, a character by its proxy.
func _check_keys(t: TestContext, mirror: MeshCarrier) -> void:
	var table := mirror.proxies_of(t.object(&"table"))
	var chair := mirror.proxies_of(t.object(&"chair"))
	t.check(
		table.size() == 1 and _label(table[0]) == "TableMesh",
		"a table is shown by the builder of its own key, not the furniture kind's",
	)
	t.check(
		chair.size() == 1 and _label(chair[0]) == "KindMesh",
		"an armchair, with no key of its own, is shown by the furniture kind's builder",
	)
	var person := mirror.proxies_of(t.actor(&"a"))
	t.check(
		person.is_empty(),
		"a kind no builder answers is shown by nothing (no stand-in)",
	)


## A floor's builder gives its mesh, standing at the floor's corner (the floor's own origin).
func _check_floor(t: TestContext, mirror: MeshCarrier) -> void:
	var floors := t.world.get_tree().get_nodes_in_group(&"floors")
	if not t.require(not floors.is_empty(), "premise: the arena has a floor"):
		return
	var shown := mirror.proxies_of(floors[0])
	if not t.require(
			shown.size() == 1 and _label(shown[0]) == "FloorMesh",
			"the floor is shown by its builder",
	):
		return
	var corner := (floors[0] as Node2D).global_position
	t.expect_near(
		shown[0].global_position.x,
		corner.x,
		0.5,
		"the floor's mesh is at its corner (x)",
	)
	t.expect_near(
		shown[0].global_position.z,
		corner.y,
		0.5,
		"the floor's mesh is at its corner (z)",
	)


## A node that is no body: followed, written only on a change, hidden, freed.
func _check_track(t: TestContext, mirror: MeshFollower) -> void:
	var item := Node2D.new()
	t.world.add_child(item)
	item.global_position = Vector2(300, 100)
	var before := mirror.count
	var shown := mirror.track(item, func(_node: Node2D) -> Node3D: return _named("ItemMesh"))
	t.require(shown != null and mirror.count == before + 1, "a tracked node has one mesh")
	await t.frames(2)
	t.expect_near(shown.global_position.x, 300.0, 0.5, "the tracked mesh stands on the node (x)")
	t.expect_near(shown.global_position.z, 100.0, 0.5, "the tracked mesh stands on the node (z)")
	item.global_position = Vector2(340, 130)
	item.rotation = 0.5
	await t.frames(2)
	t.expect_near(shown.global_position.x, 340.0, 0.5, "it follows the node (x)")
	t.expect_near(shown.global_position.z, 130.0, 0.5, "it follows the node (z)")
	t.expect_near(shown.rotation.y, -0.5, 0.01, "it turns with the node (a 2D turn is -angle)")
	# Written only when the transform changed: a still node costs no write.
	var wrote_still := false
	for i in 3:
		await t.frames(1)
		var still := mirror.mesh_of(item)
		var at := still.transform
		mirror.update()
		wrote_still = wrote_still or mirror.written > 0 and still.transform != at
	t.check(not wrote_still and mirror.written == 0, "a still tracked node is not written")
	item.visible = false
	await t.frames(2)
	t.check(not shown.visible, "a hidden node hides its mesh")
	item.visible = true
	await t.frames(2)
	t.check(shown.visible, "and shows it again")
	item.queue_free()
	await t.frames(3)
	t.check(mirror.count == before and not is_instance_valid(shown), "a freed node's mesh is freed")


## A group's nodes are tracked as they join, the ones already there at once.
func _check_group(t: TestContext, mirror: MeshFollower) -> void:
	var early := Node2D.new()
	early.name = "Early"
	early.add_to_group(&"mesh_probe")
	t.world.add_child(early)
	early.global_position = Vector2(100, 100)
	mirror.track_group(&"mesh_probe", func(_n: Node2D) -> Node3D: return _named("GroupMesh"))
	var late := Node2D.new()
	late.name = "Late"
	late.add_to_group(&"mesh_probe")
	t.world.add_child(late)
	late.global_position = Vector2(200, 150)
	await t.frames(3)
	for node: Node2D in [early, late]:
		var own := _meshes(mirror, node)
		if t.require(
			own.size() == 1 and _label(own[0]) == "GroupMesh",
			"%s is tracked" % node.name,
		):
			t.expect_near(own[0].global_position.x, node.global_position.x, 0.5, "and stands on it")


## `track_group` called before `follow()` finds the group's nodes that are already in the world.
func _check_group_before_follow(t: TestContext) -> void:
	var there := Node2D.new()
	there.add_to_group(&"mesh_probe_before")
	t.world.add_child(there)
	there.global_position = Vector2(60, 60)
	var body := WallProbe.new()  # a physics body of the group too: shown by the builder, once
	body.add_to_group(&"mesh_probe_before")
	t.world.add_child(body)
	body.global_position = Vector2(700, 460)
	var mirror := _follower(t)
	var built: Array[int] = [0]
	mirror.track_group(&"mesh_probe_before", func(_n: Node2D) -> Node3D:
		built[0] += 1
		return _named("EarlyMesh")
	)
	mirror.follow(t.world)
	await t.frames(3)
	t.expect_eq(built[0], 2, "each node of the group is built once (the node and the body)")
	var own := _meshes(mirror, there)
	t.check(
		own.size() == 1 and _label(own[0]) == "EarlyMesh",
		"a node already in the group when the follower starts is tracked",
	)
	body.queue_free()


## The finer key is for furniture alone: a wall that carries a `look.art` of "table" is never shown
## by the table's builder.
func _check_key_is_for_furniture(t: TestContext) -> void:
	var wall := WallProbe.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(80, 24)
	shape.shape = rect
	wall.add_child(shape)
	t.world.add_child(wall)
	wall.global_position = Vector2(400, 60)
	var mirror := _mirror(t)
	mirror.builders[&"furniture:table"] = func(_b: Node2D) -> Node3D: return _named("TableMesh")
	mirror.carry(t.world)
	await t.frames(3)
	var own := mirror.proxies_of(wall)
	t.check(
		own.all(func(mesh: Node3D) -> bool: return _label(mesh) != "TableMesh"),
		"a wall is not given a furniture mesh by the art id it carries",
	)
	wall.queue_free()
