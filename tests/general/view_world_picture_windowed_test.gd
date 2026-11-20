extends GameTest
## The picture is the same in the twins' world as in a world of its own (#194 del2d-b, windowed
## only: the headless renderer draws nothing). A furnished house shown by Main's `View3D` with its
## lights, the picture read back from the view; then the viewport takes a world of its own (the
## copy of the twins') and the picture is read again: the same pixels. So sharing the twin space's
## `World3D` changes nothing that is drawn (the meshes, the lights, the shadows, the pixel post).
## The static classes' meshes ride the twins' world, which a world of the view's own would not
## hold, so the mirror follows them here (`MirrorConfig.carry_meshes` off: what
## `twin_carried_picture_windowed` compares the carried picture against).
## Environment: `VIEW_WORLD_SHOT=<dir>` saves both pictures. Run:
## `tools/run_tests.sh --windowed --id=general/view_world_picture_windowed`.

const MAIN_VIEW3D := preload("res://scenes/main_view3d.gd")
const SEEDS: Array[int] = [3, 7]
## Frames the picture settles for after the camera or the world is set.
const SETTLE := 20
## Pixels (of a 0 to 255 channel) a pixel may differ by, and how many of them may.
const TOLERANCE := 1
const MAX_DIFFERING := 0


func describe() -> Dictionary:
	return {
		"name": "The 3D picture is the same in the twins' world as in its own (windowed)",
		"description": "A furnished house drawn by the 3D view in the twin space's world, then in "
			+ "a world of the view's own: the picture's pixels are the same. Windowed only.",
		"tags": ["render", "3d", "twins", "windowed"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.set_static(MirrorConfig, &"carry_meshes", false)
	s.house(SEEDS[0])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	await t.frames(2)
	var camera := Camera2D.new()
	camera.position = _middle(t.world.rooms)
	t.world.add_child(camera)
	camera.make_current()
	var view := MAIN_VIEW3D.new()
	t.world.add_child(view)
	view.begin(camera)
	view.mirror_world(t.world)
	view.light_world(t.world, SEEDS[0], t.world.rooms)
	t.world.visible = false
	await t.frames(SETTLE)
	t.check(
		view.viewport.find_world_3d() == t.world.twin_space().find_world_3d(),
		"premise: the view draws the twins' world",
	)
	# the lights flicker: held still, the two pictures stand at the same instant of them
	view.lighting.process_mode = Node.PROCESS_MODE_DISABLED
	await t.frames(2)
	var shared := _picture(view)
	var again := _picture(view)
	t.check(_differing(shared, again) == 0, "premise: a picture of the same world holds still")
	view.viewport.own_world_3d = true
	await t.frames(SETTLE)
	t.check(
		view.viewport.find_world_3d() != t.world.twin_space().find_world_3d(),
		"premise: the view now draws a world of its own",
	)
	var own := _picture(view)
	var dir := OS.get_environment("VIEW_WORLD_SHOT")
	if dir != "":
		shared.save_png(dir.path_join("shared.png"))
		own.save_png(dir.path_join("own.png"))
	t.expect_eq(shared.get_size(), own.get_size(), "the pictures are the same size")
	var differing := _differing(shared, own)
	t.check(
		differing <= MAX_DIFFERING,
		"the picture is the same in either world (%d pixels differ)" % differing,
	)
	var tones := {}
	for y in range(0, shared.get_height(), 8):
		for x in range(0, shared.get_width(), 8):
			tones[shared.get_pixel(x, y).to_html(false)] = true
	t.check(tones.size() >= 8, "premise: the picture holds a world (%d tones)" % tones.size())


## The middle of the rooms' bounds.
func _middle(rooms: Array) -> Vector2:
	var box := Rect2()
	for i in rooms.size():
		var rect := Rect2(rooms[i].get("rect", Rect2()))
		box = rect if i == 0 else box.merge(rect)
	return box.get_center()


## The picture the view shows now.
func _picture(view: CanvasLayer) -> Image:
	RenderingServer.force_draw(false)
	return view.shown.get_texture().get_image()


## How many pixels of `a` differ from `b` by more than `TOLERANCE` in any channel.
func _differing(a: Image, b: Image) -> int:
	var count := 0
	var slack := float(TOLERANCE) / 255.0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > slack or absf(p.g - q.g) > slack or absf(p.b - q.b) > slack:
				count += 1
	return count
