extends GameTest
## The textured toon's colour rule (`toon_tex.gdshader`; Art, windowed only: headless compiles no
## shader): an OPAQUE texel is the art times the instance's `base_color`, the mesh's vertex colour
## ignored (a furniture mesh carries its parts' tones there, which the art already paints); a CLEAR
## texel is `base_color` times the vertex colour. A box with green vertices wears a picture red on
## its left half and clear on its right, twice: with a white `base_color` and with a tinted one.
## Run: `tools/run_tests.sh --windowed --id=art/toon_tex_vertex_colour_windowed`.

const SIZE := 160
const HEIGHT := 20.0
const WHITE_AT := Vector3(-30, 0, 0)
const TINT_AT := Vector3(30, 0, 0)
const TINT := Color(0.5, 1.0, 0.25)
const PITCH := -80.0


func describe() -> Dictionary:
	return {
		"name": "An opaque texel ignores the vertex colour, a clear one shows it (windowed)",
		"description": "Red art on green vertices: the art's texel is red (not black), tinted by "
			+ "base_color; the clear texel is green times base_color. Windowed only.",
		"tags": ["art", "3d", "render", "windowed"],
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
	var camera := _scene(view)
	await t.frames(4)
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var art_white := _pixel(image, camera, WHITE_AT + Vector3(-8, HEIGHT, 0))
	var clear_white := _pixel(image, camera, WHITE_AT + Vector3(8, HEIGHT, 0))
	var art_tint := _pixel(image, camera, TINT_AT + Vector3(-8, HEIGHT, 0))
	var clear_tint := _pixel(image, camera, TINT_AT + Vector3(8, HEIGHT, 0))
	t.check(
		art_white.r > art_white.g * 1.5 and art_white.r > art_white.b * 1.5,
		"an opaque red texel is red, not red times the green vertices (is %s)" % art_white,
	)
	t.check(
		clear_white.g > clear_white.r * 1.5 and clear_white.g > clear_white.b * 1.5,
		"a clear texel is the green vertex colour (is %s)" % clear_white,
	)
	t.check(
		absf(art_tint.r / art_white.r - TINT.r) < 0.15,
		"the opaque texel is times base_color: red %.2f of the white one's (want %.2f)"
			% [art_tint.r / art_white.r, TINT.r],
	)
	t.check(
		absf(clear_tint.g - clear_white.g) < 0.05 and clear_tint.g > clear_tint.r * 1.5,
		"the clear texel is green times base_color: green stays, (is %s from %s)" % [
			clear_tint,
			clear_white,
		],
	)


func _scene(view: SubViewport) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = 700.0
	camera.size = float(SIZE)
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
	var pitch := deg_to_rad(-PITCH)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * 300.0
	view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	view.add_child(sun)
	var ground := MeshKit.new().box(MeshKit.volume(Rect2(-100, -100, 200, 200), -2, 2), Color.WHITE)
	view.add_child(MeshNodes.instance(ground.build(), Color(0.45, 0.45, 0.45), false))
	var picture := _picture()
	for entry: Array in [[WHITE_AT, Color.WHITE], [TINT_AT, TINT]]:
		var mesh := MeshKit.new().box(
			MeshKit.volume(Rect2(-16, -16, 32, 32), 0, HEIGHT), Color(0, 1, 0)
		)
		var box := MeshNodes.textured(
			mesh.build(), picture, Rect2(-16, -16, 32, 32), { "tint": entry[1] }
		)
		box.position = entry[0]
		view.add_child(box)
	return camera


## 2 x 1: red on the left, clear on the right.
func _picture() -> ImageTexture:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color(1, 0, 0, 1))
	image.set_pixel(1, 0, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## The picture's pixel where the world point `at` is.
func _pixel(image: Image, camera: Camera3D, at: Vector3) -> Color:
	var screen := camera.unproject_position(at)
	return image.get_pixel(clampi(int(screen.x), 0, SIZE - 1), clampi(int(screen.y), 0, SIZE - 1))
