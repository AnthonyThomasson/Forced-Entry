extends GameTest
## Each twin space is a Jolt space of its own (#194, interface 29): Jolt solves its
## contacts in the order of the slots its bodies hold and reuses a freed body's slot, so worlds that
## shared one space (the main window's `World3D`) gave different results for the same scene
## depending on what ran in the process before (a Von replay then missed at the last float bit).
## The same box scene is dropped in a twin space, then in one built after two other worlds came and
## went: the settled poses hash alike. A world's twin space is not the main window's.


func describe() -> Dictionary:
	return {
		"name": "A twin space is a physics space of its own: the same scene settles the same",
		"description": "25 boxes dropped on a floor settle to the same poses in a twin space built "
			+ "after two other worlds came and went as in the first; the twin space's 3D world is "
			+ "not the window's, and two live twin spaces do not share one.",
		"tags": ["twins", "3d", "determinism"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	await t.frames(2)
	var twins: TwinSpace = t.world.twin_space()
	t.check(
		twins.find_world_3d() != t.world.get_viewport().find_world_3d(),
		"the stage's twin space has a 3D world of its own, not the window's",
	)
	var other := TwinSpace.new()
	t.world.add_child(other)
	t.check(
		other.find_world_3d().space != twins.find_world_3d().space,
		"two live twin spaces are two physics spaces",
	)
	other.queue_free()
	await t.frames(2)
	var first := await _settled(t, 25)
	await _settled(t, 17)
	await _settled(t, 31)
	var again := await _settled(t, 25)
	t.expect_eq(again, first, "the box scene settled to the same poses after other worlds ran")


## A twin space built under the world, 25 (or `count`) boxes dropped on a floor in it, the hash of
## their poses once 240 frames have passed; the space is freed after.
func _settled(t: TestContext, count: int) -> int:
	var space := TwinSpace.new()
	t.world.add_child(space)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(2000, 10, 2000)
	floor_shape.shape = slab
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -5, 0)
	space.add_child(floor_body)
	var bodies: Array[RigidBody3D] = []
	for i in count:
		var box := RigidBody3D.new()
		box.mass = 5.0 + i
		box.gravity_scale = 42.3
		var shape := CollisionShape3D.new()
		var cuboid := BoxShape3D.new()
		cuboid.size = Vector3(30, 40, 30)
		shape.shape = cuboid
		box.add_child(shape)
		box.position = Vector3(15 * (i % 5), 20 + 25 * floori(i / 5.0), 11 * (i % 3))
		box.linear_velocity = Vector3(3.1 * (i % 4), 0, 2.3)
		space.add_child(box)
		bodies.append(box)
	await t.frames(240)
	var poses := ""
	for box in bodies:
		poses += var_to_str(box.global_transform.origin) + ","
	space.queue_free()
	await t.frames(2)
	return poses.hash()
