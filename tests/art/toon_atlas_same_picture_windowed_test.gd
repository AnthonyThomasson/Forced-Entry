extends GameTest
## The textured toon reads its art from one texture array (`ToonAtlas`) by texel, where a material
## of its own sampled the texture: the picture is the same. In a district, held still, each frame is
## drawn with the atlas and again with every textured node on a material of its own: no pixel
## differs but a tie on a texel's edge, and such ties count as the same picture. Where a pixel falls
## exactly between two texels, the shader's float picks one and the sampler the other: 4 and 20
## pixels of one 2560 wide frame, in 2x2 blocks (one art pixel) between neighbouring shades. `TIES`
## is that allowance; a shader that read one texel off turns about 350000. After the first size the
## array is made anew with more layers, as a long run grows it, and the next frames are compared
## from the new one. Windowed only.

const Frozen := preload("res://tests/_render/frozen_frame.gd")
const SIZES: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(2560, 1440)]
## The most pixels of a frame a tie on a texel's edge may turn.
const TIES := 64

## The standalone materials made, by texture, tiling and cut-out.
var _own: Dictionary = {}
## Nodes, in no tree, whose page-sized textures grow the array.
var _fill: Array[Node] = []


func describe() -> Dictionary:
	return {
		"name": "The atlased textured toon draws the picture a texture each drew",
		"description": "Held frames of a district with the art in the atlas and with each texture "
			+ "on its own material are the same but for texel-edge ties. Windowed only.",
		"tags": ["art", "render", "3d"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.district(4)
	s.switch(&"nav.rebake", false)
	s.lock_interaction([&"camera"])
	# armed figures by the first spot, so the picture holds characters and guns too
	for i in 3:
		var at := Frozen.CENTRE + Vector2(Frozen.RADIUS - 40.0 * i, 30.0 * i)
		s.actor(StringName("figure%d" % i), &"puppet", at, { "start_slot": 3 })


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := Frozen.view(t)
	var original := DisplayServer.window_get_size()
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await t.frames(10)
		for turn: float in Frozen.TURNS:
			await Frozen.hold(t, view, turn)
			await _compare(t, "%d wide, %.1f round" % [size.x, turn])
		if size == SIZES[0]:
			await _grow(t)
	for node in _fill:
		node.free()
	DisplayServer.window_set_size(original)
	Frozen.release(t)


## The held frame with the atlas and with each texture on its own material.
func _compare(t: TestContext, label: String) -> void:
	var atlased := await Frozen.picture(t)
	var swapped := _own_materials(t)
	var apart := await Frozen.picture(t)
	for entry: Array in swapped:
		(entry[0] as GeometryInstance3D).material_override = entry[1]
	t.require(swapped.size() > 100, "premise: nodes wear the atlas (%d)" % swapped.size())
	t.require(_lit(atlased) > 0.05, "premise: the frame draws the district, not black")
	var differ := Frozen.differing(atlased, apart)
	t.check(differ <= TIES, "%s: only texel-edge ties differ (%d pixels)" % [label, differ])


## Fill pages until the array has to be made anew.
func _grow(t: TestContext) -> void:
	var layers := ToonAtlas.array().get_layers()
	var side := PixelPostConfig.atlas_page
	for i in layers + 1:
		var texture := ImageTexture.create_from_image(
			Image.create(side, side, false, Image.FORMAT_RGBA8)
		)
		_fill.append(MeshNodes.textured(BoxMesh.new(), texture, Rect2(0, 0, 8, 8)))
	await RenderingServer.frame_post_draw
	t.require(
		ToonAtlas.array().get_layers() > layers,
		"premise: the array was made anew (%d layers, were %d)" % [
			ToonAtlas.array().get_layers(), layers,
		],
	)


## The mean of a coarse grid of `image`'s pixels.
func _lit(image: Image) -> float:
	var small := image.duplicate()
	small.resize(48, 32, Image.INTERPOLATE_NEAREST)
	var total := 0.0
	for y in 32:
		for x in 48:
			total += small.get_pixel(x, y).get_luminance()
	return total / float(48 * 32)


## Put every node wearing the atlas on a material sampling its own texture; returns
## `[node, the material it wore]` for each.
func _own_materials(t: TestContext) -> Array:
	var out: Array = []
	var root := t.world.get_tree().root
	for node: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		var worn := node.material_override as ShaderMaterial
		if worn == null or worn.get_shader_parameter(&"atlased") != true:
			continue
		var texture := MeshNodes.shown_texture(node)
		var key := "%d|%s|%s" % [
			texture.get_instance_id(),
			worn.get_shader_parameter(&"tiled"),
			worn.get_shader_parameter(&"cutout"),
		]
		if not _own.has(key):
			var made := worn.duplicate() as ShaderMaterial
			made.set_shader_parameter(&"atlased", false)
			made.set_shader_parameter(&"albedo_texture", texture)
			_own[key] = made
		node.material_override = _own[key]
		out.append([node, worn])
	return out
