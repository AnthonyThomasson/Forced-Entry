extends GameTest
## A played match in the 3D render mode, with the player's view and debug overlays on, drawn in a
## real window while the camera turns a quarter on a press of E (windowed only: the headless
## renderer draws nothing and compiles no shader, so an error in the flat overlays shows only here).
## Main run whole in a `SubViewport` the size of the window, a match with a human started with 3D
## chosen by its spec, Debug overlays toggled on, the camera framing the human; after the camera has
## turned a quarter of the way round the picture is read back: it holds the 3D floor and walls, the
## view's cone clear of the composite, the ground outside it dimmed but still there (not black), and
## the log gate fails the test on any
## shader or engine error or warning. With `RENDER3D_SHOT=<file.png>` set it saves the picture.
## Run: `tools/run_tests.sh --windowed --id=general/render_3d_turn_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_render_3d_turn_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 3 },
	"invaders": { "count": 3 },
}
## Frames of play before the camera turns, and the seconds the quarter turn is given.
const PLAY_FRAMES := 180
const TURN_SECONDS := 1.0
## What the picture must show: tones on a grid of samples, the share that is not the background
## colour, and the share of near-black pixels: outside the cone the composite dims the 3D scene
## (`RenderConfig.unseen_dim`) instead of blacking it out, so the ground shows there, darker.
const MIN_TONES := 8
const MIN_NOT_BACKGROUND := 0.04
const MAX_BLACK := 0.35


func describe() -> Dictionary:
	return {
		"name": "A played 3D match with the view and overlays on draws while the camera turns "
			+ "(windowed)",
		"description": "Main run whole in a window over a played 3D match, vision and debug "
			+ "overlays on, E held to turn the camera a quarter turn: the picture holds the 3D "
			+ "world, dimmed outside the cone and not black, and no shader or engine error is "
			+ "logged. Windowed only.",
		"tags": ["render", "3d", "vision", "overlays", "windowed"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(GroundLayer, &"enabled", false)
	s.switch(&"vision.enabled", true)
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var window := SubViewport.new()
	window.size = SIZE
	window.world_2d = World2D.new()
	window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(window)
	var main := MainProbe.open(window)
	MainProbe.setup_menu(main).queue_free()  # a scripted start: the window is not wanted
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.set_script(CameraScript)
	main.add_child(camera)
	camera.make_current()
	var spec := SPEC.duplicate(true)
	spec["render"] = Settings.RENDER_3D
	spec["human"] = { "node": main.get_node("Player"), "side": &"invader", "lead": false }
	var built: Dictionary = await main.start_match(spec)
	if not t.require(not built.is_empty(), "a played match started in 3D"):
		return
	for flag: String in _flags():
		main.set_overlay(flag, true)
	await t.frames(PLAY_FRAMES)
	var view: CanvasLayer = main.get_node("View3D")
	var before: float = view.rig.yaw
	Input.action_press("camera_turn_right")
	await t.frames(3)
	Input.action_release("camera_turn_right")
	await t.seconds(TURN_SECONDS)
	t.expect_near(
		wrapf(view.rig.yaw - before, -180.0, 180.0), 90.0, 0.001, "E turned the camera a quarter"
	)
	await RenderingServer.frame_post_draw
	_check_picture(t, window.get_texture().get_image())
	await MainProbe.close(t, window)


## The debug overlays toggled on: the usual few, none with `RENDER3D_PLAIN` set (the view alone).
func _flags() -> Array:
	if OS.get_environment("RENDER3D_PLAIN") != "":
		return []
	return ["show_vision", "show_nav_holes", "show_contacts", "show_tactics"]


## The picture holds the world, with the cone clear of the composite's black.
func _check_picture(t: TestContext, image: Image) -> void:
	var shot := OS.get_environment("RENDER3D_SHOT")
	if shot != "":
		image.save_png(shot)
	var background := RenderLightConfig.background_color
	var tones := {}
	var other := 0
	var black := 0
	var samples := 0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			var pixel := image.get_pixel(x, y)
			tones[pixel.to_html(false)] = true
			samples += 1
			if pixel.r + pixel.g + pixel.b < 0.03:
				black += 1
			elif absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(
				pixel.b - background.b
			) >= 0.05:
				other += 1
	t.check(tones.size() >= MIN_TONES, "the picture has many tones (%d)" % tones.size())
	var share := float(other) / float(maxi(samples, 1))
	t.check(share >= MIN_NOT_BACKGROUND, "the cone shows the world (%.0f%%)" % (share * 100.0))
	var dark := float(black) / float(maxi(samples, 1))
	t.check(
		dark <= MAX_BLACK,
		"outside the cone the ground is dimmed, not black (%.0f%% black)" % (dark * 100.0),
	)
