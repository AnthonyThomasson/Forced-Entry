extends GameTest
## A carrier given a world with no twin space has no twin to carry on: it shows nothing, and a
## `remirror` of a body asks nothing of a space it never had (#194, interface 27).


func describe() -> Dictionary:
	return {
		"name": "A carrier with no twin space carries nothing and builds nothing again",
		"description": "carry() of a world with no twin space meshes nothing, and remirror() of a "
			+ "body is a no-op rather than a call on a missing space.",
		"tags": ["mirror", "3d", "carrier"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	await t.frames(3)
	var lone := SubViewport.new()
	lone.own_world_3d = true
	t.world.add_child(lone)
	var root := Node2D.new()
	lone.add_child(root)
	var carrier := MeshCarrier.new()
	var asked: Array = []
	carrier.builders[MeshKinds.FURNITURE] = func(body: Node2D) -> Node3D:
		asked.append(body)
		return Node3D.new()
	lone.add_child(carrier)
	carrier.carry(root)
	var chair := Node2D.new()  # a handle no space twins
	root.add_child(chair)
	carrier.remirror(chair)
	await t.frames(3)
	t.expect_eq(carrier.count, 0, "nothing is carried")
	t.check(asked.is_empty(), "no builder is asked")
	t.check(carrier.mesh_of(chair) == null, "the chair has no mesh")
