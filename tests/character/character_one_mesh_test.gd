extends GameTest
## A character's body is drawn as one mesh, not one per part (#194 perf, Art `PartSkin`,
## `domain-character/body-mesh.md`): the body's node holds that one mesh, the held item's and the
## drop shadow; the mesh has every shown part's vertices in one surface, grows and shrinks with
## the parts a look shows, and the pose the shader is given is the parts' own, moved when a part
## moves. The picture is judged in a window (`character_mesh_windowed_test.gd`).


func describe() -> Dictionary:
	return {
		"name": "A character's body is drawn as one mesh",
		"description": "One mesh instance draws every shown part of a body, posed by the parts' "
			+ "own transforms, and follows an outfit that shows more or fewer of them.",
		"tags": ["mirror", "3d", "render", "character", "meshkit"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.set_static(CharacterPostureConfig, &"change_time", 0.0)
	s.actor(&"one", &"puppet", Vector2(200, 200), { "facing": Vector2.RIGHT, "start_slot": 3 })
	s.actor(&"two", &"puppet", Vector2(400, 200), { "facing": Vector2.RIGHT, "start_slot": 3 })
	s.von_script([])


func run(t: TestContext) -> void:
	var one := t.actor(&"one")
	one.wardrobe.outfit.set_ids({ "body": &"shirt", "pants": &"jeans", "feet": &"shoes" })
	t.puppet(&"one").aim_at(Vector2(2000, 200))
	await t.seconds(0.5)
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := MeshCarrier.new()
	view.add_child(mirror)
	CharacterMeshes.register(mirror.builders)
	mirror.carry(t.world)
	await t.frames(3)
	var body := mirror.mesh_of(one) as BodyMesh
	if not t.require(body != null, "the character has a body"):
		return
	var skin := _one_instance(t, body)
	if skin == null:
		return
	_check_surface(t, body, skin, "undressed")
	_check_pose(t, body, skin)
	var plain := _vertices(skin)
	one.wardrobe.outfit.set_ids({
		"body": &"shirt", "pants": &"jeans", "vest": &"plate_carrier",
		"front_plate": &"ceramic_iv", "head": &"helmet", "feet": &"boots",
	})
	await t.frames(4)
	t.check(
		_vertices(skin) > plain,
		"a vest, plate, helmet and boots add to the one mesh (%d > %d)" % [_vertices(skin), plain],
	)
	_check_surface(t, body, skin, "dressed")
	t.puppet(&"one").walk(Vector2.DOWN)
	await t.seconds(0.4)
	_check_pose(t, body, skin)
	_check_reach(t, body)
	_check_culled_by(t, body, skin)
	t.puppet(&"one").stop()
	t.puppet(&"one").set_posture(&"crouch")
	t.puppet(&"one").shoot()
	await t.seconds(0.4)
	_check_reach(t, body)
	_check_culled_by(t, body, skin)
	one.take_damage(1000.0)
	await t.seconds(0.6)
	t.require(one.is_dead and one.anatomy.ragdoll != null, "premise: it fell as a ragdoll")
	_check_culled_by(t, body, skin)


## The box the engine culls the one mesh by holds every shown part where it is posed (a part
## outside it vanishes at the edge of the screen), and is not much larger than the body, so a body
## just off the screen costs no draw.
func _check_culled_by(t: TestContext, body: BodyMesh, skin: MeshInstance3D) -> void:
	var parts := AABB()
	var outside: Array[int] = []
	var box := skin.custom_aabb
	for index in BodyMesh.CROWN + 1:
		var part: MeshPart = body.part(index)
		if not part.visible:
			continue
		var at := part.transform * part.mesh.get_aabb()
		parts = at if parts.size == Vector3.ZERO else parts.merge(at)
		if not box.encloses(at):
			outside.append(index)
	t.check(outside.is_empty(), "every shown part is in the culling box (outside: %s)" % [outside])
	var past := maxf(
		(parts.position - box.position)[(parts.position - box.position).max_axis_index()],
		(box.end - parts.end)[(box.end - parts.end).max_axis_index()],
	) / RenderConfig.unit
	t.check(past < 40.0, "the box is within 40 px of the parts on every side (%.1f px)" % past)


## All a standing body draws is within the reach it gives the mirror, which skips posing it while
## the camera does not reach that sphere.
func _check_reach(t: TestContext, body: BodyMesh) -> void:
	var drawn: Array[AABB] = []
	for index in BodyMesh.CROWN + 1:
		var part: MeshPart = body.part(index)
		if part.visible:
			drawn.append(part.transform * part.mesh.get_aabb())
	for node: MeshInstance3D in [body.held(), body.get_node("DropShadow")]:
		if node.visible and node.mesh != null:
			drawn.append(node.transform * node.mesh.get_aabb())
	var farthest := 0.0
	for box: AABB in drawn:
		for corner in 8:
			farthest = maxf(farthest, box.get_endpoint(corner).length())
	t.check(
		farthest < body.mirror_reach(),
		"all of it is within its reach (%.1f of %.1f units)" % [farthest, body.mirror_reach()],
	)


## The body's one drawn mesh: the only child that is not the held item's node or the drop shadow.
func _one_instance(t: TestContext, body: BodyMesh) -> MeshInstance3D:
	var others: Array[MeshInstance3D] = []
	for child: Node in body.get_children():
		if child != body.held() and child.name != &"DropShadow":
			others.append(child as MeshInstance3D)
	if not t.require(
		others.size() == 1,
		"one mesh instance draws the body's parts (there are %d)" % others.size(),
	):
		return null
	return others[0]


## One surface holding exactly the vertices of the shown parts' solids.
func _check_surface(t: TestContext, body: BodyMesh, skin: MeshInstance3D, when: String) -> void:
	t.expect_eq(skin.mesh.get_surface_count(), 1, "%s: one surface, so one draw" % when)
	var want := 0
	for index in BodyMesh.CROWN + 1:
		var part: MeshPart = body.part(index)
		if part.visible:
			var arrays := (part.mesh as ArrayMesh).surface_get_arrays(0)
			want += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	t.expect_eq(_vertices(skin), want, "%s: it holds every shown part's vertices" % when)


## The pose the shader is given for each shown part is that part's transform (four columns).
func _check_pose(t: TestContext, body: BodyMesh, skin: MeshInstance3D) -> void:
	var material := skin.material_override as ShaderMaterial
	var pose: PackedVector3Array = material.get_shader_parameter(&"part_pose")
	var wrong := 0
	for index in BodyMesh.CROWN + 1:
		var part: MeshPart = body.part(index)
		if not part.visible:
			continue
		var at := index * 4
		var given := Transform3D(Basis(pose[at], pose[at + 1], pose[at + 2]), pose[at + 3])
		if not given.is_equal_approx(part.transform):
			wrong += 1
	t.expect_eq(wrong, 0, "the shader is posed by the parts' own transforms")
	t.check(
		body.part(BodyMesh.HEAD).position.y > body.part(BodyMesh.TORSO).position.y,
		"premise: the parts are posed, the head over the pelvis",
	)


func _vertices(skin: MeshInstance3D) -> int:
	var arrays := (skin.mesh as ArrayMesh).surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
