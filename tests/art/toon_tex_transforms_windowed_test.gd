extends GameTest
## The textured toon under a node's own transform, a batch, a fade and a long tiled side (windowed
## only: headless compiles no shader; #193 phase 2b, Art). Orthographic camera 80 degrees down:
##  - a box turned 45 degrees and stretched 2.5 x 0.8 wears its picture in MODEL space: the four
##    quadrants sit where the turned, stretched model puts them;
##  - a textured batch (MultiMesh), its parts at three yaws, shows the picture on each part, turned
##    with it;
##  - a textured node at fade 1, 0.5 and 0 shows all, half and none of its pixels;
##  - the south side of a long tiled box repeats the art's edge along its length (a black and a
##    white texel in turn), not one smeared texel column.
## The log gate fails the test on any shader or engine error. Run: `tools/run_tests.sh --windowed
## --id=art/toon_tex_transforms_windowed`. With `TEXTOON_SHOTS=<dir>` set it saves
## `toon_tex_transforms.png` there.

const SIZE := 192
const RED := Color(0.9, 0.1, 0.1)
const GREEN := Color(0.1, 0.8, 0.1)
const BLUE := Color(0.1, 0.1, 0.9)
const YELLOW := Color(0.9, 0.85, 0.1)
const PITCH := -80.0
const BOX_HEIGHT := 20.0
const FADES := { -30.0: 1.0, -5.0: 0.5, 20.0: 0.0 }


func describe() -> Dictionary:
	return {
		"name": "A textured box turned and stretched, a batch, a fade, a tiled side (windowed)",
		"description": "The textured toon in model space: a turned, stretched box and a batch's "
			+ "parts wear the picture with their transform, a textured node fades by dither, and "
			+ "a long tiled side repeats the art's edge. Windowed only.",
		"tags": ["art", "3d", "render", "windowed", "meshkit"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
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
	var camera := _camera_and_sun(view)
	var boxed := _stretched_box(view)
	var batch := _batch(view)
	_fading_boxes(view)
	_tiled_side(view)
	await t.frames(4)
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var folder := OS.get_environment("TEXTOON_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png("%s/toon_tex_transforms.png" % folder)
	_check_stretched(t, image, camera, boxed)
	_check_batch(t, image, camera, batch)
	_check_fade(t, image, camera)
	_check_tiled_side(t, image, camera)


func _camera_and_sun(view: SubViewport) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(SIZE)
	camera.near = 1.0
	camera.far = 700.0
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
	camera.position = Vector3(0, sin(deg_to_rad(-PITCH)), cos(deg_to_rad(-PITCH))) * 300.0
	view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	view.add_child(sun)
	var ground := MeshKit.new().box(MeshKit.volume(Rect2(-100, -100, 200, 200), -2, 2), Color.WHITE)
	view.add_child(MeshNodes.instance(ground.build(), Color(0.45, 0.45, 0.45), false))
	return camera


## 16 x 16: red, green, blue and yellow quadrants (top left, top right, bottom left, bottom right).
func _picture() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			image.set_pixel(x, y, [[RED, GREEN], [BLUE, YELLOW]][y >> 3][x >> 3] as Color)
	return ImageTexture.create_from_image(image)


func _box(footprint: Rect2, height: float) -> Mesh:
	return MeshKit.new().box(MeshKit.volume(footprint, 0, height), Color.WHITE).build()


func _stretched_box(view: SubViewport) -> Node3D:
	var footprint := Rect2(-8, -8, 16, 16)
	var node := MeshNodes.textured(_box(footprint, BOX_HEIGHT), _picture(), footprint)
	node.position = Vector3(-50, 0, -40)
	node.rotation.y = PI / 4.0
	node.scale = Vector3(2.5, 1.0, 0.8)
	view.add_child(node)
	return node


## Three parts of one batch, at yaws 0, 180 and 90 degrees.
func _batch(view: SubViewport) -> MultiMeshInstance3D:
	var footprint := Rect2(-12, -12, 24, 24)
	var node := MeshNodes.batch(_box(footprint, 12.0), 3)
	MeshNodes.textured(node, _picture(), footprint)
	var yaws := [0.0, PI, PI / 2.0]
	for i in 3:
		MeshNodes.batch_place(node, i, Vector3(-50.0 + 50.0 * i, 0, 40), yaws[i])
	MeshNodes.batch_show(node, 3)
	view.add_child(node)
	return node


func _fading_boxes(view: SubViewport) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(RED)
	var red := ImageTexture.create_from_image(image)
	for z: float in FADES:
		var node := MeshNodes.textured(
			_box(Rect2(-8, -8, 16, 16), 6.0), red, Rect2(-8, -8, 16, 16)
		)
		node.position = Vector3(60, 0, z)
		MeshNodes.fade(node, FADES[z])
		view.add_child(node)


## A 64 x 8 box 40 tall, tiled by a 2 x 2 checker over 8 px tiles (a texel 4 px).
func _tiled_side(view: SubViewport) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(0, 0, Color.WHITE)
	image.set_pixel(1, 1, Color.WHITE)
	var node := MeshNodes.textured(
		_box(Rect2(-32, -4, 64, 8), 40.0),
		ImageTexture.create_from_image(image),
		Rect2(-32, -4, 8, 8),
		{ "tiled": true },
	)
	node.position = Vector3(0, 0, 0)
	view.add_child(node)


## The pixel of the picture under the world point `at`.
func _pixel(image: Image, camera: Camera3D, at: Vector3) -> Color:
	var screen := camera.unproject_position(at)
	return image.get_pixel(clampi(int(screen.x), 0, SIZE - 1), clampi(int(screen.y), 0, SIZE - 1))


## Whether the lit `pixel` is dominated by the channels `want` is.
func _is(pixel: Color, want: Color) -> bool:
	for channel in 3:
		var mine: float = pixel[channel]
		var theirs: float = want[channel]
		if theirs > 0.5 and mine < pixel.get_luminance() * 0.8:
			return false
		if theirs < 0.3 and mine > maxf(pixel.r, maxf(pixel.g, pixel.b)) * 0.6:
			return false
	return true


func _check_stretched(t: TestContext, image: Image, camera: Camera3D, node: Node3D) -> void:
	for corner: Array in [[-4, -4, RED], [4, -4, GREEN], [-4, 4, BLUE], [4, 4, YELLOW]]:
		var at := node.to_global(Vector3(corner[0], BOX_HEIGHT, corner[1]))
		var pixel := _pixel(image, camera, at)
		t.check(_is(pixel, corner[2]), "the stretched box at model (%d, %d) is %s (is %s)" % [
			corner[0], corner[1], corner[2], pixel])


func _check_batch(
	t: TestContext,
	image: Image,
	camera: Camera3D,
	node: MultiMeshInstance3D,
) -> void:
	for i in 3:
		var part := node.multimesh.get_instance_transform(i)
		for corner: Array in [[-6, -6, RED], [6, -6, GREEN], [-6, 6, BLUE], [6, 6, YELLOW]]:
			var at := node.global_transform * part * Vector3(corner[0], 12.0, corner[1])
			var pixel := _pixel(image, camera, at)
			t.check(_is(pixel, corner[2]), "batch part %d at model (%d, %d) is %s (is %s)" % [
				i, corner[0], corner[1], corner[2], pixel])


## The share of the 16 px box at `z` that is red, not the floor's grey.
func _red_share(image: Image, camera: Camera3D, z: float) -> float:
	var red := 0
	var total := 0
	for dx in range(-7, 7):
		for dz in range(-7, 7):
			var pixel := _pixel(image, camera, Vector3(60 + dx, 6.0, z + dz))
			total += 1
			red += 1 if pixel.r > pixel.g * 1.8 else 0
	return float(red) / float(total)


func _check_fade(t: TestContext, image: Image, camera: Camera3D) -> void:
	var whole := _red_share(image, camera, -30.0)
	var half := _red_share(image, camera, -5.0)
	var none := _red_share(image, camera, 20.0)
	t.check(whole > 0.9, "a textured box at fade 1 is whole (%.2f)" % whole)
	t.check(absf(half - 0.5) < 0.15, "at fade 0.5 it shows half its pixels (%.2f)" % half)
	t.check(none < 0.05, "at fade 0 it shows none (%.2f)" % none)


func _check_tiled_side(t: TestContext, image: Image, camera: Camera3D) -> void:
	# The side's bottom-row texels run black, white, black, white... every 4 px along x from -32.
	var shades := []
	for x in [-30.0, -26.0, -22.0, 18.0, 22.0]:
		shades.append(_pixel(image, camera, Vector3(x, 20, 4)).get_luminance())
	t.check(
		shades[1] > shades[0] + 0.05,
		"the tiled side's white texel is lighter than the black (%s)" % [shades],
	)
	t.check(shades[2] < shades[1] - 0.05, "and it goes dark again (%s)" % [shades])
	t.check(
		shades[4] > shades[3] + 0.05,
		"and repeats far down the side, no smeared column (%s)" % [shades],
	)
