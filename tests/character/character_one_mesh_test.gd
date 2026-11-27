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
