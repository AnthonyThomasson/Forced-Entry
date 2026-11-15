extends GameTest
## The toon material's and the kit decal's shadows, fade and glow, and a batch (windowed only: the
## headless renderer draws nothing and compiles no shader, so a shader error shows only here; #193,
## Art, interface 27). A flat floor under a sun with shadows and an orthographic camera:
##  - a decal lies in the light and another in a tall box's shadow: the shadowed one is darker (a
##    decal is lit and shadowed like the surface it lies on);
##  - a box faded 1 is whole, 0.5 shows half its pixels (an ordered dither), 0 none;
##  - a box with a glow is brighter than the same box without, in the same light;
##  - a batch of small boxes draws the first parts it is told to show, where it put them.
## The log gate fails the test on any shader or engine error. Run: `tools/run_tests.sh --windowed
## --id=art/toon_decal_fade_glow_windowed`. With `MESHKIT_SHOT=<file.png>` set it saves the picture.

const SIZE := 128
## Screen pixels of 3D `(x, z)` for an ortho camera 100 units tall over a 128 px picture.
const SCALE := 1.28
const FLOOR_COLOR := Color(0.75, 0.75, 0.7)
const RED := Color(0.85, 0.15, 0.15)


func describe() -> Dictionary:
	return {
		"name": "A decal takes the shadow, fade dithers, glow lights and a batch draws (windowed)",
		"description": "A floor under a shadowed sun: a decal in a box's shadow is darker than "
			+ "one in the light; a box at fade 1, 0.5 and 0 shows all, half and none of its "
			+ "pixels; a glowing box is brighter than a plain one; a batch draws the parts it "
			+ "shows. Windowed only.",
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
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(view)
	var sun := _lights_and_camera(view)
	var shade := _scene(view, sun)
	await t.frames(3)
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	_check_shadowed_decal(t, image, shade)
	_check_fade(t, image)
	_check_glow(t, image)
	_check_batch(t, image)
	var shot := OS.get_environment("MESHKIT_SHOT")
	if shot != "":
		image.save_png(shot)


## The sun (with shadows reaching the whole picture) and the top-down camera; returns the sun.
func _lights_and_camera(view: SubViewport) -> DirectionalLight3D:
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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0
	view.add_child(sun)
	return sun


## The floor, a tall box casting a shadow, a decal in the light and one in the shadow, three faded
## boxes, a plain and a glowing box and a batch. Returns where the shadowed decal is.
func _scene(view: SubViewport, sun: DirectionalLight3D) -> Vector2:
	var ground := _box(Rect2(-90, -90, 180, 180), -2.0, 2.0, FLOOR_COLOR)
	view.add_child(MeshNodes.instance(ground, Color.WHITE, false))
	var tall := _box(Rect2(-8, -8, 16, 16), 0.0, 30.0, Color(0.6, 0.6, 0.6))
	view.add_child(MeshNodes.instance(tall))
	# The way the sun's light runs along the ground: the shadow falls that way, 30 px of height
	# long.
	var along := sun.global_transform.basis * Vector3.FORWARD
	var heading := Vector2(along.x, along.z).normalized()
	var patch := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	patch.fill(Color(1, 1, 1, 1))
	var texture := ImageTexture.create_from_image(patch)
	for at: Vector2 in [heading * 14.0, -heading * 14.0]:
		var frame := MeshNodes.surface_frame(Vector3(at.x, 0.0, at.y))
		view.add_child(MeshNodes.decal(Vector2(6, 6), frame, texture, RED))
	_fade_and_glow(view)
	_batch(view)
	return heading * 14.0


## Three boxes faded 1, 0.5 and 0, and a plain and a glowing grey one.
func _fade_and_glow(view: SubViewport) -> void:
	var faded := { Vector2(30, 30): 1.0, Vector2(30, 10): 0.5, Vector2(10, 35): 0.0 }
	for at: Vector2 in faded:
		var footprint := Rect2(at - Vector2(8, 8), Vector2(16, 16))
		var node := MeshNodes.instance(_box(footprint, 0.0, 6.0, RED))
		MeshNodes.fade(node, faded[at])
		view.add_child(node)
	var grey := _box(Rect2(-8, -8, 16, 16), 0.0, 6.0, Color(0.5, 0.5, 0.5))
	var plain := MeshNodes.instance(grey)
	plain.position = Vector3(-30, 0, 30)
	view.add_child(plain)
	var glowing := MeshNodes.instance(grey)
	glowing.position = Vector3(-30, 0, 10)
	MeshNodes.glow(glowing, Color(0, 1, 0))
	view.add_child(glowing)


## A batch of three small boxes, the first two shown.
func _batch(view: SubViewport) -> void:
	var batch := MeshNodes.batch(_box(Rect2(-4, -4, 8, 8), 0.0, 4.0, RED), 3)
	for i in 3:
		MeshNodes.batch_place(batch, i, Vector3(-35, 0, -35 + 15 * i))
	MeshNodes.batch_show(batch, 2)
	view.add_child(batch)


func _box(footprint: Rect2, base: float, height: float, color: Color) -> Mesh:
	return MeshKit.new().box(MeshKit.volume(footprint, base, height), color).build()


## A decal in the box's shadow is darker than one in the light.
func _check_shadowed_decal(t: TestContext, image: Image, shaded: Vector2) -> void:
	var dark := image.get_pixel(_px(shaded.x), _px(shaded.y)).srgb_to_linear().get_luminance()
	var bright := image.get_pixel(_px(-shaded.x), _px(-shaded.y)).srgb_to_linear().get_luminance()
	t.check(bright > 0.0, "premise: the decal in the light draws")
	t.check(
		dark < bright * 0.85,
		"a decal in a shadow is darker than one in the light (%.3f against %.3f)" % [dark, bright],
	)


## The share of pixels of the 16 px box at `centre` that are the box's red, not the floor's.
func _red_share(image: Image, centre: Vector2) -> float:
	var red := 0
	var total := 0
	for x in range(_px(centre.x - 7), _px(centre.x + 7)):
		for y in range(_px(centre.y - 7), _px(centre.y + 7)):
			var pixel := image.get_pixel(x, y)
			total += 1
			red += 1 if pixel.r > pixel.g * 1.8 else 0
	return float(red) / float(total)


func _check_fade(t: TestContext, image: Image) -> void:
	var whole := _red_share(image, Vector2(30, 30))
	var half := _red_share(image, Vector2(30, 10))
	var none := _red_share(image, Vector2(10, 35))
	t.check(whole > 0.95, "a box at fade 1 is whole (%.2f)" % whole)
	t.check(absf(half - 0.5) < 0.1, "a box at fade 0.5 shows half its pixels (%.2f)" % half)
	t.check(none < 0.02, "a box at fade 0 shows none (%.2f)" % none)


func _check_glow(t: TestContext, image: Image) -> void:
	var plain := image.get_pixel(_px(-30), _px(30))
	var glowing := image.get_pixel(_px(-30), _px(10))
	t.check(
		glowing.g > plain.g + 0.25 and glowing.g > glowing.r + 0.2,
		"a glowing box is green and brighter than a plain one (%s against %s)" % [glowing, plain],
	)


func _check_batch(t: TestContext, image: Image) -> void:
	for i in 3:
		var pixel := image.get_pixel(_px(-35), _px(-35 + 15 * i))
		var drawn := pixel.r > pixel.g * 1.8
		t.check(drawn == (i < 2), "batch part %d is %s" % [i, "drawn" if i < 2 else "not shown"])


func _px(world: float) -> int:
	return int(float(SIZE) * 0.5 + world * SCALE)
