extends GameTest
## The bodies that move carry their meshes too (#194, interface 27 and 29): a free piece's
## mesh is a child of its `PieceBody`, a standing door's of its `DoorBody`, and a door knocked down
## takes it to the `DoorSlab` that replaces the leader, with no transform of its own: the picture is
## where the twin is, tilted and swung with it, and the mirror writes nothing for it (`written` is
## 0). A world no view looks at builds no mesh.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const SHELF_AT := Vector2(150, 200)
const MIDDLE := Vector2(400, 300)
const HINGE := Vector2(400, 280)
## Plan px a mesh may stand off its twin.
const NEAR := 0.01


func describe() -> Dictionary:
	return {
		"name": "A moving twin carries its mesh",
		"description": "With a view, a free piece's mesh is a child of its PieceBody (tipped with "
			+ "it), a door's of its DoorBody (swung with it) and a fallen door's of the DoorSlab; "
			+ "the mesh has no transform of its own and the mirror writes nothing; a world with "
			+ "no view builds no mesh; a mirror in a world of its own follows as before.",
		"tags": ["mirror", "render3d", "twins", "3d", "furniture", "door", "carriers"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": MIDDLE, "width": 52.0,
		"door": {
			"name": "swing", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.object(&"shelf", "bookshelf", SHELF_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var twins := TwinSpace.of_world(t.world)
	if not t.require(twins != null, "premise: the world has a twin space"):
		return
	await t.frames(3)
	var shelf := t.object(&"shelf")
	var door := t.object(&"swing")
	if not t.require(
		TwinSpace.twin_for(shelf) is PieceBody and TwinSpace.twin_for(door) is DoorBody,
		"premise: a free piece and a standing door",
	):
		return
	for body: Node in [shelf, door]:
		t.check(
			TwinSpace.twin_for(body).find_children("*", "MeshInstance3D", true, false).is_empty(),
			"with no view %s's twin carries no mesh" % body.name,
		)
	var mirror := _view(t)
	mirror.carry(t.world)
	await t.frames(4)
	_check_carried(t, mirror, shelf, "the free piece")
	_check_carried(t, mirror, door, "the standing door")
	await _check_tipped(t, mirror, shelf)
	await _check_placed(t, mirror, shelf)
	await _check_retwinned(t, mirror, shelf)
	await _check_swung(t, mirror, door)
	await _check_fallen(t, mirror, door)


func _view(t: TestContext) -> MeshCarrier:
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()  # drawn in the twins' world
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	ObjectMeshes.register(mirror.builders)
	view.add_child(mirror)
	return mirror


func _check_carried(t: TestContext, mirror: MeshCarrier, body: Node, what: String) -> void:
	var twin := TwinSpace.twin_for(body)
	var mesh := mirror.mesh_of(body)
	if not t.require(mesh != null and twin != null, "premise: %s has a mesh and a twin" % what):
		return
	t.check(mesh.get_parent() == twin, "%s's mesh is a child of its twin" % what)
	t.check(
		mesh.transform.is_equal_approx(Transform3D.IDENTITY),
		"%s's mesh has no transform of its own" % what,
	)
	t.check(mesh.is_inside_tree() and mesh.visible, "and is in the tree and shown")
	t.expect_eq(mirror.proxies_of(body).size(), 1, "%s has one mesh" % what)


## Whether `mesh` stands at its twin's pose (it has none of its own).
func _on(mesh: Node3D, twin: Node3D) -> bool:
	return mesh.global_transform.is_equal_approx(twin.global_transform)


func _check_tipped(t: TestContext, mirror: MeshCarrier, shelf: Node2D) -> void:
	Knockback.push(shelf, Vector2(9000.0, 0.0), Vector2.ZERO, Probe.top(shelf) - 4.0)
	var off := 0
	var written := 0
	var frames := 0
	while frames < 600 and not (frames > 20 and Probe.asleep(shelf)):
		await t.frames(1)
		frames += 1
		var now := mirror.mesh_of(shelf)
		if now == null or not _on(now, TwinSpace.twin_for(shelf)):
			off += 1
		written += mirror.written
	await t.frames(3)
	t.require(Probe.lean(shelf) > 60.0, "premise: it lies over (%.0f degrees)" % Probe.lean(shelf))
	var mesh := mirror.mesh_of(shelf)
	t.expect_eq(off, 0, "the mesh was at its twin's pose every frame of the tip")
	t.expect_eq(written, 0, "the mirror wrote nothing while the piece fell")
	t.check(mesh.get_parent() == TwinSpace.twin_for(shelf), "still its twin's child")
	var lean := rad_to_deg(acos(clampf(mesh.global_transform.basis.y.y, -1.0, 1.0)))
	t.check(lean > 60.0, "its mesh lies on its side too (%.0f degrees)" % lean)


## A sleeping piece a script puts elsewhere (its twin is parked): the twin takes it up within the
## slow look (`TwinSpace.PARK_SPREAD` frames), upright, and its mesh stands with it.
func _check_placed(t: TestContext, mirror: MeshCarrier, shelf: Node2D) -> void:
	t.require(Probe.asleep(shelf), "premise: the shelf lies asleep")
	var there := Vector2(250.0, 650.0)
	shelf.global_position = there
	await t.frames(TwinSpace.PARK_SPREAD + 4)
	var mesh := mirror.mesh_of(shelf)
	var twin := TwinSpace.twin_for(shelf)
	t.check(mesh.get_parent() == twin, "the mesh is still its twin's child")
	var plan := PlanSpace.plan_of(mesh.global_position)
	t.check(plan.distance_to(there) < 1.0, "the mesh stands where it was put (%s)" % plan)
	t.check(Probe.lean(shelf) < 1.0, "upright again (%.1f degrees)" % Probe.lean(shelf))
	t.check(_on(mesh, twin), "at its twin's pose")


## A piece twinned again (its old twin is freed): its mesh moves to the new twin in the same call,
## so no frame draws without it (a retwin made after the mirror's own update included), one mesh
## for the body, nothing logged.
func _check_retwinned(t: TestContext, mirror: MeshCarrier, shelf: Node2D) -> void:
	var before := mirror.count
	var old := TwinSpace.twin_for(shelf)
	var mesh_then := mirror.mesh_of(shelf)
	TwinSpace.retwin(shelf)
	var at_once := TwinSpace.twin_for(shelf)
	t.check(
		mesh_then.get_parent() == at_once and mesh_then.is_inside_tree(),
		"the same mesh is on the new twin at once, in the tree",
	)
	await t.frames(1)
	t.check(
		is_instance_valid(mesh_then) and mesh_then.is_inside_tree(),
		"and after the old twin went",
	)
	await t.frames(3)
	var twin := TwinSpace.twin_for(shelf)
	t.check(twin != null and twin != old, "premise: the piece has a new twin")
	var mesh := mirror.mesh_of(shelf)
	t.check(mesh != null and mesh.get_parent() == twin, "its mesh is on the new twin")
	t.expect_eq(mirror.count, before, "still one mesh a body")
	t.check(_on(mesh, twin), "at the new twin's pose")


func _check_swung(t: TestContext, mirror: MeshCarrier, door: Node2D) -> void:
	var twin := TwinSpace.twin_for(door)
	door.toggle(null)
	var off := 0
	var written := 0
	var mid := 0
	for i in 120:
		await t.frames(1)
		var now := mirror.mesh_of(door)
		if now == null or not _on(now, twin):
			off += 1
		written += mirror.written
		if door.angle() > 20.0 and door.angle() < door.open_angle - 20.0:
			mid += 1
		if not door.swing.moving() and i > 10:
			break
	t.require(mid >= 3, "premise: the door was seen swinging (%d frames mid-swing)" % mid)
	t.expect_eq(off, 0, "the door's mesh was at its leader's pose every frame of the swing")
	t.expect_eq(written, 0, "the mirror wrote nothing while the door swung")
	var mesh := mirror.mesh_of(door)
	var plan := PlanSpace.plan_of(mesh.global_position)
	t.check(
		plan.distance_to(door.global_position) < 1.0,
		"and the 2D door is where the mesh is (%s, %s)" % [plan, door.global_position],
	)


func _check_fallen(t: TestContext, mirror: MeshCarrier, door: Node2D) -> void:
	var before := mirror.count
	var felled_mesh := mirror.mesh_of(door)
	door.take_blow(&"kick", 10_000.0, Vector2(2200.0, 0.0), 40.0)
	await t.frames(2)
	var slab := TwinSpace.twin_for(door)
	if not t.require(slab is DoorSlab, "premise: the felled door is a DoorSlab"):
		return
	var mesh := mirror.mesh_of(door)
	t.check(mesh != null and mesh.get_parent() == slab, "its mesh is on the slab")
	t.check(mesh == felled_mesh, "the very mesh that hung on the leaf's body (carried over)")
	t.expect_eq(mirror.count, before, "the leader's replacement adds and drops no mesh")
	var off := 0
	var written := 0
	for _i in 600:
		await t.frames(1)
		if not _on(mirror.mesh_of(door), TwinSpace.twin_for(door)):
			off += 1
		written += mirror.written
		if Probe.asleep(door):
			break
	await t.frames(3)
	t.expect_eq(off, 0, "the mesh was at the slab's pose every frame of the fall")
	t.expect_eq(written, 0, "the mirror wrote nothing while it fell")
	t.check(Probe.lean(door) > 10.0, "premise: it fell over (%.0f degrees)" % Probe.lean(door))
	var up := mirror.mesh_of(door).global_transform.basis.y.y
	var lean := rad_to_deg(acos(clampf(up, -1.0, 1.0)))
	t.check(
		absf(lean - Probe.lean(door)) < 0.5,
		"the door's mesh leans as its slab does (%.1f, %.1f degrees)" % [lean, Probe.lean(door)],
	)
	t.expect_eq(mirror.count, before, "still one mesh a body")
