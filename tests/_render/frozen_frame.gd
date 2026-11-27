extends RefCounted
## Shared by the windowed tests that hold the same picture drawn two ways (not a test): Main's 3D
## view over the test's district, the camera put at a spot and the world stopped there
## (`Engine.time_scale` 0: no physics step, no light rhythm, no pose), so two frames of it differ
## only by what the test changed between them.

const ViewScript := preload("res://scenes/main_view3d.gd")
## The spots round `CENTRE` the camera is put at: the angle (turns) and the yaw there.
const CENTRE := Vector2.ZERO
const RADIUS := 520.0
const TURNS: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8]


## The view of `t.world`'s district, lit, following its camera with the camera's own scripts off
## and the 2D world hidden.
static func view(t: TestContext) -> CanvasLayer:
	var camera := t.world.get_viewport().get_camera_2d()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.zoom = Vector2.ONE
	var made: CanvasLayer = ViewScript.new()
	t.world.add_child(made)
	made.begin(camera)
	made.mirror_world(t.world)
	made.light_world(t.world, 10, WorldGen.district_rooms(t.world.district))
	t.world.visible = false
	return made


## Run the world with the camera at spot `turn` until it has settled, then stop it.
static func hold(t: TestContext, shown: CanvasLayer, turn: float) -> void:
	Engine.time_scale = 1.0
	shown.lighting.set_process(true)
	var camera := t.world.get_viewport().get_camera_2d()
	camera.global_position = CENTRE + Vector2.from_angle(TAU * turn) * RADIUS
	shown.rig.yaw = 45.0 + 360.0 * turn
	await t.frames(30)
	Engine.time_scale = 0.0
	# the lights' rhythms and flickers step by their own clock: stopped with the world
	shown.lighting.set_process(false)


## The window's picture after the next few frames of the stopped world.
static func picture(t: TestContext) -> Image:
	for i in 4:
		await t.world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := t.world.get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## Run the world again and give the camera back.
static func release(t: TestContext) -> void:
	Engine.time_scale = 1.0
	var camera := t.world.get_viewport().get_camera_2d()
	camera.set_process(true)
	camera.set_physics_process(true)


## How many pixels of `a` and `b` differ.
static func differing(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return a.get_width() * a.get_height()
	var left := a.get_data()
	var right := b.get_data()
	if left == right:
		return 0
	var count := 0
	for i in range(0, left.size(), 3):
		if left[i] != right[i] or left[i + 1] != right[i + 1] or left[i + 2] != right[i + 2]:
			count += 1
	return count
