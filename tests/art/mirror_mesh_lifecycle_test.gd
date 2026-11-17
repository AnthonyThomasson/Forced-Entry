extends GameTest
## What the mirror does with a domain's own mesh over its life (#193, interface 27,
## `domain-art/mesh-hook.md`): an own mesh is hidden while every collision shape of its body is
## disabled (a seated character) and shown while one is enabled; a mesh that changes without its
## body's transform changing is updated by `mirror_update(body)` each frame it is shown (a sleeping
## or static body's too, not a hidden one's) and rebuilt on demand by `remirror(node)`; a body that
## dies hides its mesh unless the mesh's `on_body_died(body)` says to stay; a node tracked by
## `track` survives a reparent (parked while out of the tree, shown again on re-entry) and is
## freed when it is freed out of the tree; a group's nodes are shown when they are in it by the end
## of their `_ready` and a later joiner by `remirror`; a group builder that returns null leaves a
## physics body its proxy.

const Mortal := preload("res://tests/_art/art_mortal_probe.gd")
const MeshProbe := preload("res://tests/_art/art_mesh_probe.gd")
const WallProbe := preload("res://tests/_art/art_wall_probe.gd")
const ReadyJoiner := preload("res://tests/_art/art_ready_group_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The mirror keeps a domain's own mesh in step: update, rebuild, death, reparent",
		"description": "An own mesh hides while all its body's shapes are disabled; mirror_update "
			+ "runs each frame it is shown; remirror rebuilds it; a death hides it unless it "
			+ "stays; a tracked node survives a reparent; a group tracks nodes that join in "
			+ "_ready; a null group builder leaves the proxy.",
		"tags": ["mirror", "3d", "render"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"chair", "armchair", Vector2(300, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	await t.frames(5)
	var mirror := _mirror(t)
	mirror.builders[MirrorProxy.FURNITURE] = func(body: Node2D) -> Node3D:
		var probe := MeshProbe.new()
		probe.survives_death = body.name == "Keeps"
		return probe
	mirror.builders[MirrorProxy.WALL] = func(_body: Node2D) -> Node3D: return MeshProbe.new()
	mirror.mirror(t.world)
	await t.frames(3)
	await _check_shapes(t, mirror)
	await _check_update_hook(t, mirror)
	await _check_remirror(t, mirror)
	await _check_death(t, mirror)
	await _check_reparent(t, mirror)
	await _check_group(t)


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror


func _mesh_of(mirror: WorldMirror, node: Node) -> Node3D:
	var shown := mirror.proxies_of(node)
	return shown[0] if shown.size() == 1 else null


## A body with two shapes: its own mesh shows while either is enabled and hides when both are off.
func _check_shapes(t: TestContext, mirror: WorldMirror) -> void:
	var body := AnimatableBody2D.new()
	body.position = Vector2(600, 100)
	var shapes: Array[CollisionShape2D] = []
	for i in 2:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		body.add_child(shape)
		shapes.append(shape)
	t.world.add_child(body)
	await t.frames(3)
	var mesh := _mesh_of(mirror, body)
	if not t.require(mesh != null, "premise: a two-shape body has one own mesh"):
		return
	t.check(mesh.visible, "an own mesh shows while its shapes are enabled")
	shapes[0].disabled = true
	await t.frames(2)
	t.check(mesh.visible, "and while one of two is still enabled")
	shapes[1].disabled = true
	await t.frames(2)
	t.check(not mesh.visible, "an own mesh is hidden while every shape of its body is disabled")
	shapes[1].disabled = false
	await t.frames(2)
	t.check(mesh.visible, "and shown again once one is enabled")
	body.visible = false
	await t.frames(2)
	t.check(not mesh.visible, "and hidden while its body's own visible is off")
	body.queue_free()


## `mirror_update(body)` runs every frame the mesh shows: a sleeping furniture piece's, a static
## wall's, not a hidden one's.
func _check_update_hook(t: TestContext, mirror: WorldMirror) -> void:
	var chair := t.object(&"chair")
	var probe := _mesh_of(mirror, chair) as MeshProbe
	if not t.require(probe != null, "premise: the chair's mesh is the probe"):
		return
	await t.frames(30)  # it falls asleep
	var calls := probe.calls
	await t.frames(6)
	t.check(probe.calls - calls >= 5, "the hook runs each frame, a sleeping body's too")
	t.check(probe.last_body == chair, "and is given the body")
	var wall := WallProbe.new()
	wall.position = Vector2(100, 400)
	t.world.add_child(wall)
	await t.frames(3)
	var wall_probe := _mesh_of(mirror, wall) as MeshProbe
	if t.require(wall_probe != null, "premise: a static wall has the probe"):
		var before := wall_probe.calls
		await t.frames(5)
		t.check(wall_probe.calls - before >= 4, "a static body's hook runs each frame too")
	chair.visible = false
	await t.frames(2)
	calls = probe.calls
	await t.frames(5)
	t.check(probe.calls == calls, "the hook does not run while the mesh is hidden")
	chair.visible = true
	wall.queue_free()


## `remirror(node)` builds the mesh again at once, the old one gone, the count as it was; for a
## tracked node through the builder it was tracked with.
func _check_remirror(t: TestContext, mirror: WorldMirror) -> void:
	var chair := t.object(&"chair")
	var old := _mesh_of(mirror, chair)
	var count := mirror.count
	mirror.remirror(chair)
	var fresh := _mesh_of(mirror, chair)
	t.check(fresh != null and fresh != old, "remirror gives the body a new mesh at once")
	t.check(mirror.count == count, "and the count is as it was")
	await t.frames(2)
	t.check(not is_instance_valid(old), "the old mesh is freed")
	var item := Node2D.new()
	t.world.add_child(item)
	var built: Array[int] = [0]
	mirror.track(item, func(_n: Node2D) -> Node3D:
		built[0] += 1
		return Node3D.new()
	)
	var first := _mesh_of(mirror, item)
	mirror.remirror(item)
	t.check(built[0] == 2 and _mesh_of(mirror, item) != first, "a tracked node is rebuilt too")
	item.queue_free()


## A body that dies: its mesh hides and stops following, unless it says to stay.
func _check_death(t: TestContext, mirror: WorldMirror) -> void:
	var gone := Mortal.new()
	gone.name = "Goes"
	var stays := Mortal.new()
	stays.name = "Keeps"
	for body: Mortal in [gone, stays]:
		body.position = Vector2(400, 300)
		t.world.add_child(body)
	await t.frames(3)
	var gone_mesh := _mesh_of(mirror, gone)
	var stays_mesh := _mesh_of(mirror, stays)
	if not t.require(gone_mesh != null and stays_mesh != null, "premise: both have a mesh"):
		return
	gone.died.emit()
	stays.died.emit()
	for body: Mortal in [gone, stays]:
		body.position = Vector2(500, 350)
	await t.frames(3)
	t.check(not gone_mesh.visible, "a body that dies hides its mesh by default")
	t.expect_near(gone_mesh.global_position.x, 400.0, 0.5, "and it no longer follows")
	t.check(stays_mesh.visible, "a mesh whose on_body_died says true stays shown")
	t.expect_near(stays_mesh.global_position.x, 500.0, 0.5, "and keeps following the body")
	gone.queue_free()
	stays.queue_free()


## A tracked node survives a reparent and a trip out of the tree; freed out of the tree it takes its
## mesh with it.
func _check_reparent(t: TestContext, mirror: WorldMirror) -> void:
	await t.frames(3)  # the bodies of the test before this one are gone
	var from := Node2D.new()
	var to := Node2D.new()
	to.position = Vector2(300, 100)
	var item := Node2D.new()
	from.add_child(item)
	t.world.add_child(from)
	t.world.add_child(to)
	var mesh := mirror.track(item, func(_n: Node2D) -> Node3D: return Node3D.new())
	var count := mirror.count
	item.reparent(to, false)
	await t.frames(3)
	t.check(_mesh_of(mirror, item) == mesh and mirror.count == count, "a reparent keeps the mesh")
	t.check(mesh.visible, "shown")
	t.expect_near(mesh.global_position.x, 300.0, 0.5, "and follows the node to its new place")
	to.remove_child(item)
	await t.frames(3)
	t.check(not mesh.visible, "out of the tree its mesh is hidden")
	to.add_child(item)
	item.position = Vector2(40, 0)
	await t.frames(3)
	t.check(mesh.visible, "and shown again when it is back")
	t.expect_near(mesh.global_position.x, 340.0, 0.5, "where the node now is")
	to.remove_child(item)
	item.free()
	await t.frames(3)
	t.check(
		not is_instance_valid(mesh) and mirror.count == count - 1,
		"a node freed out of the tree takes its mesh with it",
	)
	from.queue_free()
	to.queue_free()


## A group tracks the nodes that were in it when they entered the tree and queues no other; one that
## joins later is `remirror`ed in; a builder that returns null leaves a physics body its proxy.
func _check_group(t: TestContext) -> void:
	var mirror := _mirror(t)
	mirror.track_group(&"fx_probe", func(node: Node2D) -> Node3D:
		return null if node.has_meta(&"skip") else Node3D.new()
	)
	mirror.mirror(t.world)
	await t.frames(2)
	var member := Node2D.new()
	member.add_to_group(&"fx_probe")
	t.world.add_child(member)
	var joiner := ReadyJoiner.new()
	t.world.add_child(joiner)
	var late := Node2D.new()
	t.world.add_child(late)
	await t.frames(3)
	late.add_to_group(&"fx_probe")  # after the mirror looked
	await t.frames(3)
	t.check(_mesh_of(mirror, member) != null, "a node in the group on entry is shown")
	t.check(_mesh_of(mirror, joiner) != null, "so is one that joins its group in its own _ready")
	t.check(_mesh_of(mirror, late) == null, "a node that joins its group later is not")
	mirror.remirror(late)
	t.check(_mesh_of(mirror, late) != null, "unless it is remirrored")
	var body := WallProbe.new()
	body.set_meta(&"skip", true)
	body.add_to_group(&"fx_probe")
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	body.add_child(shape)
	t.world.add_child(body)
	await t.frames(3)
	var proxy := _mesh_of(mirror, body)
	t.check(
		proxy is MeshInstance3D and (proxy as MeshInstance3D).mesh is BoxMesh,
		"a group builder that returns null leaves a physics body its proxy",
	)
	var plain := Node2D.new()
	plain.set_meta(&"skip", true)
	plain.add_to_group(&"fx_probe")
	t.world.add_child(plain)
	await t.frames(3)
	t.check(_mesh_of(mirror, plain) == null, "and a node that is no body no mesh at all")
