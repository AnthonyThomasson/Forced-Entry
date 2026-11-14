extends GameTest
## In the 3D render mode the 2D world is hidden and not drawn, so the vision memory's capture
## `SubViewport` (UPDATE_ALWAYS, a second render of the 2D world every frame) would be a hidden
## cost with nothing to show (#193 pixelpost, interface 25: memory capture is off in 3D until
## phase 3 projects the view onto the 3D scene). Main is run whole twice over the same played
## match: with 3D chosen the capture does not update; with 2D chosen it does (the premise that
## gives the 3D result its meaning). The cone itself still runs (the sim's view is unchanged), and
## the mask, which draws only the cone, keeps updating for the ground overlay.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_vision/vision_probe.gd")
const SCRATCH := "user://settings_vision_capture_3d_test.json"
const SPEC := {
	"seed": 5,
	"side": "defender",
	"lead": false,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}


func describe() -> Dictionary:
	return {
		"name": "A 3D match stops the vision memory's capture, a 2D match keeps it",
		"description": "Interface 25: the capture SubViewport renders every frame in 2D and is "
			+ "stopped in a 3D match, whose 2D world is not drawn; the cone keeps being built.",
		"tags": ["vision", "render", "3d"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"vision.enabled", true)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	var drawn := await _capture_mode(t, Settings.RENDER_2D)
	if not t.require(drawn != -1, "premise: a 2D match with a human was built"):
		return
	t.expect_eq(drawn, SubViewport.UPDATE_ALWAYS, "a 2D match's capture updates every frame")
	var skipped := await _capture_mode(t, Settings.RENDER_3D)
	if not t.require(skipped != -1, "a 3D match with a human was built"):
		return
	t.expect_eq(skipped, SubViewport.UPDATE_DISABLED, "a 3D match's capture does not render")


## The update mode of the capture of the human's view in a played match of `render`, or -1 when no
## view was built. The cone is read too: it keeps being published in either mode.
func _capture_mode(t: TestContext, render: String) -> int:
	for old in t.world.find_children("MainViewport", "SubViewport", false, false):
		await MainProbe.close(t, old)
	var viewport := MainProbe.viewport(t)
	var main := MainProbe.open(viewport)
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	main.add_child(camera)
	Settings.render_mode = render
	var menu := MainProbe.setup_menu(main)
	if menu == null:
		return -1
	menu.start_requested.emit(SPEC.merged({ "mode": "play" }))
	if not await t.until(func() -> bool: return not Probe.views_under(viewport).is_empty(), 10.0):
		return -1
	await t.frames(3)
	var view: PlayerView = Probe.views_under(viewport)[0]
	var mode := view.capture().render_target_update_mode
	t.check(view.rebuilds() > 0 or view.starts() > 0, "%s: the cone is still built" % render)
	return mode
