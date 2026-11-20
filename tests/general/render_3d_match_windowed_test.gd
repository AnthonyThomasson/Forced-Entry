extends GameTest
## A match in the 3D render mode draws in a real window (windowed only: the headless renderer draws
## nothing and compiles no shader, so a shader or engine error in the 3D view shows only here). Main
## run whole in a SubViewport the size of the window, a Watch match started with 3D chosen, the
## camera framing the combatants; after a few seconds of play the picture the view shows is read
## back: it holds the floor, walls and bodies of the mirror (many distinct tones, most of it not the
## background), and the log gate fails the test on any shader or engine error or warning. With
## `RENDER3D_SHOT=<file.png>` set it also saves the picture. Run:
## `tools/run_tests.sh --windowed --id=general/render_3d_match_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_render_3d_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 3 },
	"invaders": { "count": 3 },
}
## Frames of play before the picture is read.
const PLAY_FRAMES := 240
## What the 3D view must show of its world: tones counted on a grid of samples, and the share of
## the samples that are not the background colour.
const MIN_TONES := 8
const MIN_NOT_BACKGROUND := 0.4


func describe() -> Dictionary:
	return {
		"name": "A match in the 3D render mode draws without shader or engine errors (windowed)",
		"description": "A Watch match started with 3D chosen, run in a window: the 3D view shows "
			+ "the mirror's floor, walls and bodies, and no shader or engine error is logged. "
			+ "Windowed only.",
		"tags": ["render", "3d", "windowed"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
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
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	t.check(not (built["world"] as Node2D).visible, "the 2D world is not drawn")
	var view := main.get_node_or_null("View3D")
	if not t.require(view != null, "Main built the 3D view"):
		return
	await t.frames(PLAY_FRAMES)
	t.check(
		view.carrier.count > 100,
		"the mirror follows the world (%d proxies)" % view.carrier.count,
	)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	_check_picture(t, window.get_texture().get_image())
	await MainProbe.close(t, window)


## The picture holds the mirror's world: many tones, most of it not the background.
func _check_picture(t: TestContext, image: Image) -> void:
	var shot := OS.get_environment("RENDER3D_SHOT")
	if shot != "":
		image.save_png(shot)
	var background := RenderLightConfig.background_color
	var tones := {}
	var other := 0
	var samples := 0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			var pixel := image.get_pixel(x, y)
			tones[pixel.to_html(false)] = true
			samples += 1
			if not _near(pixel, background):
				other += 1
	t.check(tones.size() >= MIN_TONES, "the picture has many tones (%d)" % tones.size())
	var share := float(other) / float(maxi(samples, 1))
	t.check(share >= MIN_NOT_BACKGROUND, "most of the picture is world (%.0f%%)" % (share * 100.0))


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.05
