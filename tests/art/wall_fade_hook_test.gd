extends GameTest
## What the wall fade is given by the mirror (#193 rule 9, interface 27): `MeshCarrier.built(body,
## mesh)` says each mesh a builder made for a body, and the fade (`WallFade.listen`) looks after the
## walls', doors' and furniture's, so a builder registered after the fade started still fades, and a
## character's, a vehicle's or a body that got no mesh is left alone. A shoved piece (not a
## wall) is movable for the fade's grid, a wall is not.

const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SIZE := Vector3(40, 70, 40)

var _built: Array = []


func describe() -> Dictionary:
	return {
		"name": "The wall fade takes every wall, door and furniture mesh, any builder order",
		"description": "A builder registered after the fade listens still has its walls, doors "
			+ "and furniture faded; characters and bodies with no mesh are not; movable "
			+ "pieces are told apart from fixed ones.",
		"tags": ["mirror", "3d", "render", "wall-fade"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(WallFadeConfig, &"faded_amount", 0.25)


func run(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	t.world.find_child("Arena Walls", true, false).free()  # only the bodies below are mirrored
	var mirror := MeshCarrier.new()
	var fade := WallFade.new()
	view.add_child(mirror)
	view.add_child(fade)
	fade.set_process(false)
	fade.listen(mirror)
	fade.listen(mirror)  # twice is once
	mirror.built.connect(func(body: Node, mesh: Node3D) -> void: _built.append([body, mesh]))
	# every builder is registered after the fade started listening
	mirror.builders[MeshKinds.FURNITURE] = _builder
	mirror.builders[MeshKinds.WALL] = _builder
	mirror.builders[MeshKinds.DOOR] = _builder
	var bodies := {
		"piece": _body(t, PlanProbe.handle(), "piece", Vector2(0, 24)),
		"shoved": _body(t, PlanProbe.handle(), "shoved", Vector2(2000, 40)),
		"wall": _body(t, StandInWall.new(), "wall", Vector2(0, 400)),
		"door": _body(t, PlanProbe.handle(), "door", Vector2(0, 800)),
		"bare": _body(t, PlanProbe.handle(), "bare", Vector2(0, 1600)),
	}
	bodies["door"].add_to_group(&"doors")
	mirror.carry(t.world)
	await t.frames(3)
	fade.step(0.0, 0.0, PackedVector2Array())
	_kept(t, fade, bodies)
	for i in 14:
		fade.step(0.05, 0.0, PackedVector2Array([Vector2(0, 0)]))
	var part := mirror.proxies_of(bodies["piece"])[0].get_child(0) as GeometryInstance3D
	var level: Variant = part.get_instance_shader_parameter(&"fade")
	t.expect_near(float(level), 0.25, 0.07, "the piece in the way fades")


## What the fade kept of the bodies: walls, doors and furniture with a mesh, movable as they are.
func _kept(t: TestContext, fade: WallFade, bodies: Dictionary) -> void:
	t.check(_made_for(bodies["piece"]), "premise: a mesh was built for the furniture")
	t.check(not _made_for(bodies["bare"]), "premise: none for the body whose builder gave null")
	t.expect_eq(fade.count(), 4, "the furniture, shoved piece, wall and door are kept")
	for key: String in ["piece", "shoved", "wall", "door"]:
		t.check(fade.unit_of(bodies[key].get_instance_id()) != null, "%s is kept" % key)
	t.check(not fade.unit_of(bodies["wall"].get_instance_id()).movable, "a wall is fixed")
	t.check(fade.unit_of(bodies["shoved"].get_instance_id()).movable, "a piece is movable")
	t.check(fade.unit_of(bodies["door"].get_instance_id()).movable, "a door is movable")
	t.check(fade.unit_of(bodies["bare"].get_instance_id()) == null, "a body with no mesh is not")
	var walker := Node2D.new()
	walker.name = "walker"
	t.world.add_child(walker)
	walker.add_to_group(&"characters")
	var orphan := _builder(walker)
	fade.on_built(walker, orphan)  # not in the tree: only the kind is asked
	fade.step(0.0, 0.0, PackedVector2Array())
	t.expect_eq(fade.count(), 4, "a character's mesh is not kept")
	walker.remove_from_group(&"characters")
	walker.queue_free()
	orphan.free()


func _builder(body: Node2D) -> Node3D:
	if body.name == "bare":
		return null
	var mesh := Node3D.new()
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = SIZE
	part.mesh = box
	part.position = Vector3(0, SIZE.y * 0.5, 0)
	mesh.add_child(part)
	return mesh


func _body(t: TestContext, body: Node2D, body_name: String, at: Vector2) -> Node2D:
	body.name = body_name
	body.position = at
	t.world.add_child(body)
	return body


func _made_for(body: Node) -> bool:
	return _built.any(func(pair: Array) -> bool: return pair[0] == body)


## A body the mirror reads as a wall (it has a `wall_thickness`).
class StandInWall extends Node2D:
	var wall_thickness := 8.0

	func _enter_tree() -> void:
		add_to_group(&"walls")
		add_to_group(TwinSpace.BODIES)
