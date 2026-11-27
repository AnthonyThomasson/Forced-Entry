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
## The drawn frames the stopped picture must have stayed the same before it is held, and the most
## waited for that.
const SETTLED_FRAMES := 90
const MOST_FRAMES := 600


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
	# each mesh draws itself, so a test may change one and see it: no chunk is built. The meshes are
	# offered by now, for `art/still_merge_same_picture_windowed` and its like to build
	made.carrier.merge.enabled = false
	made.light_world(t.world, 10, WorldGen.district_rooms(t.world.district))
	t.world.visible = false
	return made


## Run the world with the camera at spot `turn` until it has settled, stop it, and wait until the
## stopped picture has too.
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
	if not await settle(t.world.get_tree(), picture.bind(t)):
		t.check(false, "the stopped picture settles within %d drawn frames" % MOST_FRAMES)


## Wait until `take` (awaited: it gives the picture) has given the same one over `SETTLED_FRAMES`
## drawn frames; false if `MOST_FRAMES` are drawn first. The renderer goes on changing what the omni
## shadows look like for some frames after the first world a process draws is stopped (up to 40,
## with no node changed), so two frames compared before that may stand on either side of it. A
## drawn frame is one the main loop drew (`Engine.get_frames_drawn`) or `drawn` had to.
static func settle(tree: SceneTree, take: Callable) -> bool:
	var last: Image = await take.call()
	var start := Engine.get_frames_drawn()
	var forced := 0
	var changed_at := 0
	while true:
		for i in 10:
			forced += int(await drawn(tree))
		var now: Image = await take.call()
		var count := Engine.get_frames_drawn() - start + forced
		if differing(last, now) != 0:
			changed_at = count
		elif count - changed_at >= SETTLED_FRAMES:
			return true
		if count >= MOST_FRAMES:
			break
		last = now
	return false


## Wait until the frame being processed now is drawn. Never waits for the draw signal alone: a
## window the desktop covers is not drawn and `frame_post_draw` never comes (the stopped world would
## spin for ever, its test's clock stopped too), so a frame that ended undrawn is drawn here; true
## if it had to be.
static func drawn(tree: SceneTree) -> bool:
	var seen := [false]
	var mark := func() -> void: seen[0] = true
	RenderingServer.frame_post_draw.connect(mark)
	await tree.process_frame
	RenderingServer.frame_post_draw.disconnect(mark)
	if not seen[0]:
		RenderingServer.force_draw(false)
	return not seen[0]


## The window's picture after the next few frames of the stopped world.
static func picture(t: TestContext) -> Image:
	for i in 4:
		await t.world.get_tree().process_frame
	await drawn(t.world.get_tree())
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
