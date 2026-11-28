extends GameTest
## A character's body is drawn as one mesh, not one per part (#194 perf, Art `PartSkin`,
## `domain-character/body-mesh.md`): the body's node holds that one mesh, the held item's and the
## drop shadow; the mesh has every shown part's vertices in one surface, grows and shrinks with
## the parts a look shows, and the pose the shader is given is the parts' own, moved when a part
## moves. The mesh and its material carry each shown part's look: its colour (the textured toon's
## tint times vertex colour), its art in the atlas, the footprint that art covers and whether it is
## a cut-out; skins whose parts differ in any of these wear different looks, the same ones share.
## The picture is judged in a window (`art/part_skin_windowed`, `character_mesh_windowed_test.gd`).


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
	_check_look(t, body, skin, "undressed")
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
	_check_look(t, body, skin, "dressed")
	_check_dressed_apart(t, mirror, skin)
	_check_looks_differ(t)
	t.puppet(&"one").walk(Vector2.DOWN)
	await t.seconds(0.4)
	_check_pose(t, body, skin)
	_check_reach(t, body)
	_check_culled_by(t, body, skin)
	await _check_crouched_and_fallen(t, body, skin)


## Crouched and firing, then dead on the floor: the culling box and the reach follow.
func _check_crouched_and_fallen(t: TestContext, body: BodyMesh, skin: MeshInstance3D) -> void:
	var one := t.actor(&"one")
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
	t.expect_eq(body.mirror_reach(), INF, "a fallen body, flung anywhere, is always posed")


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


## Each shown part's vertices carry its colour and its index, and the material says where its art
## is: the part's texture, pixel for pixel, in the atlas, over the part's own footprint.
func _check_look(t: TestContext, body: BodyMesh, skin: MeshInstance3D, when: String) -> void:
	var arrays := (skin.mesh as ArrayMesh).surface_get_arrays(0)
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var material := skin.material_override as ShaderMaterial
	var at := 0
	var wrong: Array[String] = []
	for index in BodyMesh.CROWN + 1:
		var part: MeshPart = body.part(index)
		if not part.visible:
			continue
		at = _check_colour(part, index, custom, at, wrong)
		_check_art(part, index, material, wrong)
	t.check(wrong.is_empty(), "%s: every part wears its own look (%s)" % [when, wrong.slice(0, 6)])
	_require_variety(t, body, when)
	var neck: MeshPart = body.part(BodyMesh.NECK)
	var skin_colour := body.look_worn().skin.srgb_to_linear()
	var first := _first_vertex(body, BodyMesh.NECK)
	var got := Color(custom[first * 4], custom[first * 4 + 1], custom[first * 4 + 2])
	t.check(
		neck.visible and _close(got, skin_colour),
		"%s: the plain neck is the skin's colour, linear (%s of %s)" % [when, got, skin_colour],
	)


## The premise of the look's check: parts with art, a cut-out and tinted ones.
func _require_variety(t: TestContext, body: BodyMesh, when: String) -> void:
	var shown: Array = []
	for index in BodyMesh.CROWN + 1:
		if body.part(index).visible:
			shown.append(body.part(index))
	var textured := shown.filter(func(p: MeshPart) -> bool: return p.texture != null).size()
	var cutouts := shown.filter(func(p: MeshPart) -> bool: return p.cutout).size()
	var tinted := shown.filter(func(p: MeshPart) -> bool: return p.tint != Color.WHITE).size()
	t.require(
		textured > 10 and cutouts > 0 and tinted > 1,
		"%s: premise: parts with art (%d), a cut-out (%d) and tinted ones (%d)"
			% [when, textured, cutouts, tinted],
	)


## `part`'s vertices from `at` in `custom`: its colour and `index`. Returns where the next begins.
func _check_colour(
	part: MeshPart, index: int, custom: PackedFloat32Array, at: int, wrong: Array[String]
) -> int:
	var solid := (part.mesh as ArrayMesh).surface_get_arrays(0)
	var painted: PackedColorArray = solid[Mesh.ARRAY_COLOR]
	var tint := part.tint.srgb_to_linear()
	for i in painted.size():
		var k := (at + i) * 4
		var got := Color(custom[k], custom[k + 1], custom[k + 2])
		if not _close(got, tint * painted[i]):
			wrong.append("part %d colour %s, not %s" % [index, got, tint * painted[i]])
			break
		if int(custom[k + 3]) != index:
			wrong.append("part %d tagged %d" % [index, int(custom[k + 3])])
			break
	return at + painted.size()


## What `material` says of part `index`'s art against the part's own.
func _check_art(
	part: MeshPart, index: int, material: ShaderMaterial, wrong: Array[String]
) -> void:
	var regions: PackedVector4Array = material.get_shader_parameter(&"part_atlas")
	var region := regions[index]
	if part.texture == null:
		if region.z != 0.0:
			wrong.append("part %d has art it was not given" % index)
		return
	var size := Vector2(part.texture.get_size())
	if region.z != size.x or absf(region.w) != size.y:
		wrong.append("part %d art %s, not %s" % [index, Vector2(region.z, region.w), size])
		return
	if (region.w < 0.0) != part.cutout:
		wrong.append("part %d cut-out is %s" % [index, region.w < 0.0])
	var footprints: PackedVector4Array = material.get_shader_parameter(&"part_uv")
	var footprint := footprints[index]
	var rect := Vector4(
		part.rect.position.x, part.rect.position.y, part.rect.size.x, part.rect.size.y
	)
	if not footprint.is_equal_approx(rect):
		wrong.append("part %d footprint %s, not %s" % [index, footprint, rect])
	var atlas := (material.get_shader_parameter(&"atlas") as Texture2D).get_image()
	var cut := atlas.get_region(Rect2i(Vector2i(int(region.x), int(region.y)), Vector2i(size)))
	var own := part.texture.get_image()
	own.convert(Image.FORMAT_RGBA8)
	if cut.get_data() != own.get_data():
		wrong.append("part %d is not its texture's pixels in the atlas" % index)


## Where part `index`'s vertices begin in the joined surface.
func _first_vertex(body: BodyMesh, index: int) -> int:
	var first := 0
	for before in index:
		var part: MeshPart = body.part(before)
		if part.visible:
			var arrays := (part.mesh as ArrayMesh).surface_get_arrays(0)
			first += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return first


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.002 and absf(a.g - b.g) < 0.002 and absf(a.b - b.b) < 0.002


## The second character, dressed otherwise, wears its own look: its own mesh and art.
func _check_dressed_apart(t: TestContext, mirror: MeshCarrier, skin: MeshInstance3D) -> void:
	var other := mirror.mesh_of(t.actor(&"two")) as BodyMesh
	if not t.require(other != null, "premise: the second character has a body"):
		return
	var instance := _one_instance(t, other)
	if instance == null:
		return
	t.check(instance.mesh != skin.mesh, "dressed otherwise, it has its own mesh")
	_check_look(t, other, instance, "the other")


## Skins of one part each that differ only in its art, its footprint, its cut-out or its tint each
## wear what they say; two the same share one mesh.
func _check_looks_differ(t: TestContext) -> void:
	var solid := MeshKit.new().box(
		MeshKit.volume(Rect2(-8, -8, 16, 16), 0, 4), Color(0.8, 0.6, 0.4)
	).build()
	var red := _plain(Color.RED)
	var blue := _plain(Color.BLUE)
	var rect := Rect2(-8, -8, 16, 16)
	var rows := [
		["as the first", red, rect, false, Color.WHITE],
		["other art", blue, rect, false, Color.WHITE],
		["other footprint", red, Rect2(-4, -4, 8, 8), false, Color.WHITE],
		["a cut-out", red, rect, true, Color.WHITE],
		["other tint", red, rect, false, Color(0.5, 0.25, 1.0)],
		["the first again", red, rect, false, Color.WHITE],
	]
	var skins: Array[PartSkin] = []
	for row: Array in rows:
		var one := PartSkin.new(1)
		var part := one.parts[0]
		part.mesh = solid
		part.texture = row[1]
		part.rect = row[2]
		part.cutout = row[3]
		part.tint = row[4]
		one.dress()
		skins.append(one)
		var arrays := (one.node.mesh as ArrayMesh).surface_get_arrays(0)
		var wrong: Array[String] = []
		_check_colour(part, 0, arrays[Mesh.ARRAY_CUSTOM0], 0, wrong)
		_check_art(part, 0, one.node.material_override, wrong)
		t.check(wrong.is_empty(), "a skin %s wears its own look (%s)" % [row[0], wrong])
	t.check(skins[5].node.mesh == skins[0].node.mesh, "the same parts share one mesh")
	for one: PartSkin in skins:
		one.node.free()


func _plain(colour: Color) -> Texture2D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)


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
