extends GameTest
## The toon material's global hook for phase 3's vision mask, and the kit's decal (windowed only:
## the headless renderer draws nothing and compiles no shader, so a shader error in the globals or
## the decal shows only here; #193, Art, interface 27). A kit-built box under an orthographic
## camera: by default (`vision_unseen` 1) a mask changes nothing; with `ToonMask.set_mask` a black
## mask over the whole world dims the box to the brightness given; `clear()` brings it back. A
## kit decal (a red patch with an alpha-cut texture) lies on the box's top and draws in its colour,
## its transparent corner cutting through to the box. The log gate fails the test on any shader or
## engine error. Run: `tools/run_tests.sh --windowed --id=art/toon_vision_hook_windowed`. With
## `MESHKIT_SHOT=<file.png>` set it saves the picture.

const SIZE := 128
const BOX := Rect2(-30, -30, 60, 60)
const BOX_HEIGHT := 20.0
## Screen pixels of 3D `(x, z)` for an ortho camera 100 units tall over a 128 px picture.
const SCALE := 1.28


func _draw(t: TestContext) -> void:
	await t.frames(3)
	await RenderingServer.frame_post_draw


func describe() -> Dictionary:
	return {
		"name": "The vision mask hook dims the toon material and the kit's decal draws (windowed)",
		"description": "A kit box under an orthographic camera in a window: a mask changes "
			+ "nothing until unseen is set below 1, a black mask then dims it, clear restores "
			+ "it; a kit decal lies on it in its own colour with its alpha cut out. Windowed only.",
		"tags": ["art", "3d", "render", "windowed", "meshkit"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(RenderConfig, &"unit", 1.0)


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var view := _scene(t)
	await _draw(t)
	var plain := (await _picture(t, view)).get_pixel(_px(-10), _px(-10))
	# A black mask over the world with unseen 1 (the default) is no mask at all.
	var black := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	ToonMask.set_mask(ImageTexture.create_from_image(black), Rect2(-100, -100, 200, 200), 1.0)
	var open := (await _picture(t, view)).get_pixel(_px(-10), _px(-10))
	t.check(_near(plain, open), "a mask that leaves everything at 1 changes nothing")
	ToonMask.set_mask(ImageTexture.create_from_image(black), Rect2(-100, -100, 200, 200), 0.25)
	var image := await _picture(t, view)
	var dim := image.get_pixel(_px(-10), _px(-10))
	t.check(
		dim.srgb_to_linear().get_luminance() < plain.srgb_to_linear().get_luminance() * 0.5,
		"an unseen mask dims the box (%s -> %s)" % [plain, dim],
	)
	# A mask whose rect lies elsewhere leaves this ground out of it: outside the texture reads 0
	# (clamped to its edge), so what the rect does not reach is as dark as the mask says.
	ToonMask.clear()
	var back := (await _picture(t, view)).get_pixel(_px(-10), _px(-10))
	t.check(_near(plain, back), "clear shows everything again")
	t.check(not ToonMask.mask_active(), "and no mask is active")
	_check_decal(t, await _picture(t, view))
	var shot := OS.get_environment("MESHKIT_SHOT")
	if shot != "":
		(await _picture(t, view)).save_png(shot)


## The viewport the scene is in, with the kit box, a decal, a sun and the camera.
func _scene(t: TestContext) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100.0
	camera.near = 1.0
	camera.far = 600.0
	camera.position = Vector3(0, 300, 0)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 20, 0)
	view.add_child(sun)
	var solid := MeshKit.volume(BOX, 0.0, BOX_HEIGHT)
	var mesh := MeshKit.new().box(solid, Color(0.8, 0.8, 0.7)).build()
	view.add_child(MeshNodes.instance(mesh))
	var cut := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	cut.fill(Color(0.9, 0.1, 0.1, 1.0))
	cut.set_pixel(1, 1, Color(0.9, 0.1, 0.1, 0.0))
	var frame := MeshNodes.surface_frame(Vector3(10, BOX_HEIGHT, 10))
	view.add_child(
		MeshNodes.decal(Vector2(20, 20), frame, ImageTexture.create_from_image(cut))
	)
	return view


## The decal is red where its texture is opaque and shows the box where it is cut away.
func _check_decal(t: TestContext, image: Image) -> void:
	# The decal covers x, z in 0..20; its texture's top-left (opaque) quarter is x, z 0..10, its
	# bottom-right (cut) quarter x, z 10..20.
	var opaque := image.get_pixel(_px(5), _px(5))
	var cut := image.get_pixel(_px(15), _px(15))
	t.check(
		opaque.r > opaque.g * 2.0 and opaque.r > opaque.b * 2.0,
		"the decal is red where its texture is opaque (%s)" % opaque,
	)
	t.check(
		not (cut.r > cut.g * 2.0 and cut.r > cut.b * 2.0),
		"the box shows through where the texture is cut (%s)" % cut,
	)


func _px(world: float) -> int:
	return int(float(SIZE) * 0.5 + world * SCALE)


func _picture(t: TestContext, view: SubViewport) -> Image:
	await _draw(t)
	return view.get_texture().get_image()


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.03
