extends GameTest
## A body the twin space gave no twin (a non-solid piece: a rug, which never moves) that appears
## after the carrier started has its mesh placed where it stands, once, a child of the carrier
## (#194 del2d-b3c, interface 27): the carrier hears of it through `TwinSpace.untwinned`.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A twinless body spawned after the carrier is shown by a mesh where it stands",
		"description": "A bare body no builder twins, added after carry(): the carrier places its "
			+ "mesh at its pose as its own child and frees it with the body.",
		"tags": ["mirror", "3d", "carrier", "twins"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	await t.frames(3)
	var view := SubViewport.new()
	view.world_3d = TwinSpace.of_world(t.world).find_world_3d()
	t.world.add_child(view)
	var carrier := MeshCarrier.new()
	carrier.builders[MeshKinds.FURNITURE] = func(_body: Node2D) -> Node3D: return Node3D.new()
	view.add_child(carrier)
	carrier.carry(t.world)
	await t.frames(2)
	var count := carrier.count
	var rug := PlanProbe.handle()
	rug.position = Vector2(150, 90)
	t.world.add_child(rug)
	await t.frames(3)
	var mesh := carrier.mesh_of(rug)
	if not t.require(mesh != null, "the twinless body is shown by a mesh"):
		return
	t.check(mesh.get_parent() == carrier, "it is a child of the carrier")
	t.expect_near(mesh.global_position.x, 150.0, 0.5, "it stands where the body does (x)")
	t.expect_near(mesh.global_position.z, 90.0, 0.5, "it stands where the body does (z)")
	t.expect_eq(carrier.count, count + 1, "it is counted")
	rug.free()
	await t.frames(2)
	t.expect_eq(carrier.count, count, "its mesh goes with the body")
