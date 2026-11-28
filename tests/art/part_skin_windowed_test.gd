extends GameTest
## Many posed parts drawn as one mesh (`PartSkin`, `toon_parts.gdshader`; Art, windowed only:
## headless compiles no shader) show the picture the same parts show as nodes of their own
## (`MeshNodes.textured`, `MeshNodes.instance`): art over a coloured solid with a clear hole, plain
## tinted solids, a cut-out laid over another part, a part turned and stretched, a ball scaled
## unevenly (its light shows the shader's normal rule). The one scene is
## shot twice, with the nodes shown and with the skin shown, and the shots are compared pixel for
## pixel. Run: `tools/run_tests.sh --windowed --id=art/part_skin_windowed`. With
## `PART_SKIN_SHOTS=<dir>` set it saves the two pictures there.

const SIZE := 192
const PITCH := -80.0
## How far a channel may differ for a pixel to count as the same.
const SAME := 0.02
## How many pixels may differ: a texel read exactly on its edge may fall to either side.
const TIES := 12


func describe() -> Dictionary:
	return {
		"name": "Parts joined in one mesh look as nodes of their own (windowed)",
		"description": "Art, clear holes, tints, a cut-out and a turned, stretched part drawn "
			+ "by one skinned mesh match the same parts drawn one node each. Windowed only.",
		"tags": ["art", "3d", "render", "windowed", "meshkit"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()  # it builds its own view and reads its pixels
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	_stage(view)
	var empty := await _shoot(t, view)
	var parts := _parts()
	var nodes := Node3D.new()
	view.add_child(nodes)
	var skin := PartSkin.new(parts.size())
	for i in parts.size():
		var part := parts[i]
		nodes.add_child(_node_of(part))
		var joined := skin.parts[i]
		joined.mesh = part.mesh
		joined.tint = part.tint
		joined.texture = part.texture
		joined.rect = part.rect
		joined.cutout = part.cutout
		joined.transform = part.transform
	skin.dress()
	skin.pose()
	skin.node.custom_aabb = AABB(Vector3(-100, -10, -100), Vector3(200, 80, 200))
	view.add_child(skin.node)
	skin.node.visible = false
	var apart := await _shoot(t, view)
	nodes.visible = false
	skin.node.visible = true
	var one := await _shoot(t, view)
	_save(apart, "part_skin_nodes")
	_save(one, "part_skin_joined")
	t.require(
		_differing(empty, apart) > 2000,
		"premise: the parts cover much of the picture (%d pixels)" % _differing(empty, apart),
	)
	var differing := _differing(apart, one)
	t.check(
		differing <= TIES,
		"the one mesh shows the parts' picture: %d pixels differ" % differing,
	)


## A floor, the sun and the camera.
func _stage(view: SubViewport) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = 700.0
	camera.size = 130.0
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
	var pitch := deg_to_rad(-PITCH)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * 300.0
	view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	view.add_child(sun)
	var ground := MeshKit.new().box(MeshKit.volume(Rect2(-100, -100, 200, 200), -2, 2), Color.WHITE)
	view.add_child(MeshNodes.instance(ground.build(), Color(0.45, 0.45, 0.45), false))


## The parts both pictures show. A part with art is tinted white, as its art is shown as painted.
func _parts() -> Array[MeshPart]:
	var slab := _solid(Rect2(-14, -14, 28, 28), 10.0, Color(0.6, 0.3, 0.8))
	var white := _solid(Rect2(-10, -10, 20, 20), 12.0, Color.WHITE)
	var flat := _solid(Rect2(-14, -14, 28, 28), 1.0, Color(0.9, 0.9, 0.2))
	var rect := Rect2(-14, -14, 28, 28)
	var out: Array[MeshPart] = [
		_part(slab, Vector3(-34, 0, -30), { "texture": _quarters(), "rect": rect }),
		_part(white, Vector3(2, 0, -30), { "tint": Color(0.9, 0.5, 0.15) }),
		_part(slab, Vector3(36, 0, -30), { "tint": Color(0.5, 1.0, 0.4) }),
		_part(slab, Vector3(-34, 0, 10), {
			"texture": _stripes(), "rect": Rect2(-10, -6, 20, 12),
		}),
		_part(white, Vector3(6, 0, 12), { "tint": Color(0.3, 0.5, 0.9) }),
		_part(flat, Vector3(6, 14, 12), {
			"texture": _quarters(), "rect": rect, "cutout": true,
		}),
		_part(slab, Vector3(36, 0, 20), { "texture": _stripes(), "rect": rect }),
		_part(BodySolids.fetch(&"ball", {}, Color.WHITE), Vector3(-4, 6, 38), {
			"tint": Color(0.9, 0.9, 0.9),
		}),
	]
	out[7].transform.basis = Basis.from_scale(Vector3(22, 6, 9))
	out[6].transform = Transform3D(
		Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, -0.35)
			* Basis.from_scale(Vector3(0.7, 1.6, 1.2)),
		out[6].position,
	)
	return out


func _solid(area: Rect2, height: float, colour: Color) -> Mesh:
	return MeshKit.new().box(MeshKit.volume(area, 0, height), colour).build()


func _part(mesh: Mesh, at: Vector3, opts: Dictionary) -> MeshPart:
	var part := MeshPart.new()
	part.mesh = mesh
	part.transform = Transform3D(Basis.IDENTITY, at)
	part.tint = opts.get("tint", Color.WHITE)
	part.texture = opts.get("texture")
	part.rect = opts.get("rect", Rect2())
	part.cutout = opts.get("cutout", false)
	return part


## `part` as a node of its own.
func _node_of(part: MeshPart) -> GeometryInstance3D:
	var node: GeometryInstance3D
	if part.texture == null:
		node = MeshNodes.instance(part.mesh, part.tint, false)
	else:
		node = MeshNodes.textured(part.mesh, part.texture, part.rect, {
			"tint": part.tint, "cutout": part.cutout, "casts_shadow": false,
		})
	node.transform = part.transform
	return node


## 8 x 8: red, green, blue and yellow quadrants with a clear 4 x 4 hole in the middle.
func _quarters() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var colours := [[Color.RED, Color.GREEN], [Color.BLUE, Color.YELLOW]]
	for y in 8:
		for x in 8:
			var colour: Color = colours[y >> 2][x >> 2]
			if x in range(2, 6) and y in range(2, 6):
				colour = Color(0, 0, 0, 0)
			image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)


## 5 x 4: stripes of a size of its own, so two arts share one atlas.
func _stripes() -> Texture2D:
	var image := Image.create(5, 4, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in 5:
			image.set_pixel(x, y, Color.CYAN if x % 2 == 0 else Color.MAGENTA)
	return ImageTexture.create_from_image(image)


func _shoot(t: TestContext, view: SubViewport) -> Image:
	await t.frames(4)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	return view.get_texture().get_image()


func _differing(a: Image, b: Image) -> int:
	var count := 0
	for y in SIZE:
		for x in SIZE:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > SAME or absf(p.g - q.g) > SAME or absf(p.b - q.b) > SAME:
				count += 1
	return count


func _save(image: Image, name: String) -> void:
	var folder := OS.get_environment("PART_SKIN_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png("%s/%s.png" % [folder, name])
