extends GameTest
## The textured toon (`toon_tex.gdshader`, `MeshNodes.textured`; #193 phase 2b, Art, windowed only:
## headless draws nothing and compiles no shader). A hand-made 16 px picture (four coloured
## quadrants round a clear hole) on a box, a cylinder and a tiled slab under a sun with an
## orthographic camera 80 degrees down, shot at zoom 1 (one picture pixel a screen pixel) and
## zoom 3 (a texel three):
##  - the box's top shows the quadrants where the picture puts them (red top left, green top
##    right, blue bottom left, yellow bottom right) and the clear hole shows the mesh's own
##    colour (white), not the floor or a hole;
##  - its south side is no smooth block: it reads the picture's bottom edge, blue then yellow,
##    stretched down and darker than the top;
##  - the cylinder's lid shows the picture as the box does (the model's footprint, not the
##    cylinder's round outline, places it);
##  - a tiled slab repeats its 2 x 2 checker across the footprint.
## The log gate fails the test on any shader or engine error. Run: `tools/run_tests.sh --windowed
## --id=art/toon_tex_windowed`. With `TEXTOON_SHOTS=<dir>` set it saves the two pictures there
## (`toon_tex_zoom1.png`, `toon_tex_zoom3.png`).

const SIZE := 192
const RED := Color(0.9, 0.1, 0.1)
const GREEN := Color(0.1, 0.8, 0.1)
const BLUE := Color(0.1, 0.1, 0.9)
const YELLOW := Color(0.9, 0.85, 0.1)
## Where the three pieces stand (world px, the camera at zoom 1 is over the origin).
const BOX_AT := Vector3(-60, 0, 0)
const CYLINDER_AT := Vector3(0, 0, 0)
const SLAB_AT := Vector3(60, 0, 0)
const BOX_HEIGHT := 30.0
const PITCH := -80.0


func describe() -> Dictionary:
	return {
		"name": "A textured box, cylinder and tiled slab show their picture (windowed)",
		"description": "The 2D art as a texture on 3D meshes, shot at zoom 1 and 3: a box's top "
			+ "shows the quadrants where the picture puts them and the hole its vertex colour, "
			+ "its side reads the picture's edge stretched and darker, a cylinder's lid shows "
			+ "the picture, a tiled slab repeats it. Windowed only.",
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
	var camera := _scene(view)
	camera.position = _camera_at(Vector3.ZERO)
	camera.size = float(SIZE)
	var wide := await _shoot(t, view)
	_save(wide, "toon_tex_zoom1")
	_check_top(t, wide, camera, BOX_AT, 1.0)
	_check_cylinder(t, wide, camera)
	_check_slab(t, wide, camera)
	# Zoom 3: the camera over the box, a third of the world in view.
	camera.position = _camera_at(BOX_AT)
	camera.size = float(SIZE) / 3.0
	var near := await _shoot(t, view)
	_save(near, "toon_tex_zoom3")
	_check_top(t, near, camera, BOX_AT, 3.0)
	_check_side(t, near, camera)


## Where the camera stands to look at `at` along its pitch.
func _camera_at(at: Vector3) -> Vector3:
	var pitch := deg_to_rad(-PITCH)
	return at + Vector3(0, sin(pitch), cos(pitch)) * 300.0


## The floor, the three textured pieces, the sun and the camera; returns the camera.
func _scene(view: SubViewport) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 1.0
	camera.far = 700.0
	camera.rotation_degrees = Vector3(PITCH, 0, 0)
	view.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0
	view.add_child(sun)
	var ground := MeshKit.new().box(MeshKit.volume(Rect2(-100, -100, 200, 200), -2, 2), Color.WHITE)
	view.add_child(MeshNodes.instance(ground.build(), Color(0.45, 0.45, 0.45), false))
	var picture := _picture()
	var box_mesh := MeshKit.new().box(
		MeshKit.volume(Rect2(-16, -16, 32, 32), 0, BOX_HEIGHT), Color.WHITE
	)
	var box := MeshNodes.textured(box_mesh.build(), picture, Rect2(-16, -16, 32, 32))
	box.position = BOX_AT
	view.add_child(box)
	var cylinder_mesh := MeshKit.new().cylinder(Vector3.ZERO, 14.0, 20.0, Color.WHITE)
	var cylinder := MeshNodes.textured(cylinder_mesh.build(), picture, Rect2(-14, -14, 28, 28))
	cylinder.position = CYLINDER_AT
	view.add_child(cylinder)
	var slab_mesh := MeshKit.new().box(
		MeshKit.volume(Rect2(-24, -24, 48, 48), 0, 4), Color.WHITE
	)
	var slab := MeshNodes.textured(
		slab_mesh.build(), _checker(), Rect2(-24, -24, 24, 24), { "tiled": true }
	)
	slab.position = SLAB_AT
	view.add_child(slab)
	return camera


## 16 x 16: red, green, blue and yellow quadrants, a clear 4 x 4 hole in the middle.
func _picture() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var color := [[RED, GREEN], [BLUE, YELLOW]][y >> 3][x >> 3] as Color
			if x in range(6, 10) and y in range(6, 10):
				color = Color(0, 0, 0, 0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


## 2 x 2: white and black, so a repeat is its alternation.
func _checker() -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(0, 0, Color.WHITE)
	image.set_pixel(1, 1, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _shoot(t: TestContext, view: SubViewport) -> Image:
	await t.frames(4)
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


## The pixel of the picture where the world point `at` (px, a model point of a piece at `base`) is.
func _pixel(image: Image, camera: Camera3D, at: Vector3) -> Color:
	var screen := camera.unproject_position(at)
	return image.get_pixel(clampi(int(screen.x), 0, SIZE - 1), clampi(int(screen.y), 0, SIZE - 1))


func _is(pixel: Color, want: Color) -> bool:
	# The dominant channels of the wanted colour dominate the lit pixel too.
	for channel in 3:
		var mine: float = pixel[channel]
		var theirs: float = want[channel]
		if theirs > 0.5 and mine < pixel.get_luminance() * 0.8:
			return false
		if theirs < 0.3 and mine > maxf(pixel.r, maxf(pixel.g, pixel.b)) * 0.6:
			return false
	return true


func _check_top(t: TestContext, image: Image, camera: Camera3D, at: Vector3, zoom: float) -> void:
	var top := Vector3(0, BOX_HEIGHT, 0)
	var quarter := 8.0
	var lit := {}
	for corner: Array in [
		[-quarter, -quarter, RED, "top left"], [quarter, -quarter, GREEN, "top right"],
		[-quarter, quarter, BLUE, "bottom left"], [quarter, quarter, YELLOW, "bottom right"],
	]:
		var pixel := _pixel(image, camera, at + top + Vector3(corner[0], 0, corner[1]))
		lit[corner[3]] = pixel
		t.check(_is(pixel, corner[2]), "zoom %d: the box's %s is %s (is %s)" % [
			int(zoom), corner[3], corner[2], pixel])
	var hole := _pixel(image, camera, at + top)
	var spread := maxf(hole.r, maxf(hole.g, hole.b)) - minf(hole.r, minf(hole.g, hole.b))
	t.check(
		spread < 0.12 and hole.get_luminance() > 0.15,
		"zoom %d: the clear hole shows the mesh's white vertex colour (is %s)" % [int(zoom), hole],
	)


func _check_side(t: TestContext, image: Image, camera: Camera3D) -> void:
	var low := Vector3(0, BOX_HEIGHT * 0.5, 16.0)
	var left := _pixel(image, camera, BOX_AT + low + Vector3(-8, 0, 0))
	var right := _pixel(image, camera, BOX_AT + low + Vector3(8, 0, 0))
	t.check(
		_is(left, BLUE),
		"the south side's left reads the picture's bottom-left edge, blue (is %s)" % left,
	)
	t.check(
		_is(right, YELLOW),
		"the south side's right reads the bottom-right edge, yellow (is %s)" % right,
	)
	var top := _pixel(image, camera, BOX_AT + Vector3(-8, BOX_HEIGHT, 8))
	t.check(
		left.get_luminance() < top.get_luminance(),
		"the side is darker than the top's same colour (%.3f against %.3f)" % [
			left.get_luminance(), top.get_luminance()],
	)


func _check_cylinder(t: TestContext, image: Image, camera: Camera3D) -> void:
	var lid := Vector3(0, 20, 0)
	for corner: Array in [[-6, -6, RED], [6, -6, GREEN], [-6, 6, BLUE], [6, 6, YELLOW]]:
		var pixel := _pixel(image, camera, CYLINDER_AT + lid + Vector3(corner[0], 0, corner[1]))
		t.check(_is(pixel, corner[2]), "the cylinder's lid at %s is %s (is %s)" % [
			Vector2(corner[0], corner[1]), corner[2], pixel])


func _check_slab(t: TestContext, image: Image, camera: Camera3D) -> void:
	# One tile is 24 px, a texel 12: cells alternate white and black every 12 px.
	var top := Vector3(0, 4, 0)
	var shades := []
	var cells := [
		Vector2(-18, -18), Vector2(-6, -18), Vector2(-6, -6), Vector2(18, 18), Vector2(6, 6),
	]
	for cell: Vector2 in cells:
		var pixel := _pixel(image, camera, SLAB_AT + top + Vector3(cell.x, 0, cell.y))
		shades.append(pixel.get_luminance())
	t.check(shades[0] > shades[1] * 2.0, "the slab's first tile alternates white then black")
	t.check(shades[1] < shades[2] * 0.5, "...and down a row (%s)" % [shades])
	t.check(
		absf(shades[0] - shades[3]) < 0.05 or shades[3] > shades[1] * 2.0,
		"the second tile repeats the picture (%s)" % [shades],
	)


func _save(image: Image, name: String) -> void:
	var folder := OS.get_environment("TEXTOON_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png("%s/%s.png" % [folder, name])
