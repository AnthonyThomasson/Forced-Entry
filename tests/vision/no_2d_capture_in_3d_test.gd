extends GameTest
## In the 3D render mode the 2D world is hidden and not drawn, so the 2D view's parts (a capture
## `SubViewport` that renders the 2D world every frame, the memory it paints, the cone's screen mask
## and the composite over the world) would be a hidden cost with nothing to show (#193 pixelpost,
## vision-mask, interface 25): in 3D the view is only the two masks the toon shaders read
## (`ViewGround`), drawn on request. Main is run whole twice over the same played match: with 2D
## chosen the capture updates every frame (the premise that gives the 3D result its meaning); with
## 3D chosen the view has no capture, memory, mask or composite at all and no viewport of it renders
## every frame. The cone itself still runs (the sim's view is unchanged).

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
		"name": "A 3D match makes no 2D capture of the world, a 2D match keeps it",
		"description": "Interface 25: the capture SubViewport renders every frame in 2D; "
			+ "a 3D match builds none of the 2D view's parts and no viewport of its view "
			+ "updates every frame; the cone keeps being built.",
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
	var drawn := await _view_of(t, Settings.RENDER_2D)
	if not t.require(drawn != null, "premise: a 2D match with a human was built"):
		return
	t.check(drawn.capture() != null, "premise: a 2D view has a capture")
	t.expect_eq(
		drawn.capture().render_target_update_mode,
		SubViewport.UPDATE_ALWAYS,
		"a 2D match's capture updates every frame",
	)
	var flat := await _view_of(t, Settings.RENDER_3D)
	if not t.require(flat != null, "a 3D match with a human was built"):
		return
	t.check(flat.capture() == null and flat.memory() == null, "a 3D view has no capture, no memory")
	t.check(flat.mask() == null and flat.composite() == null, "and no screen mask, no composite")
	var always := flat.find_children("*", "SubViewport", true, false).filter(
		func(v: SubViewport) -> bool:
			return v.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	)
	t.expect_eq(always.size(), 0, "no viewport of the 3D view renders every frame")


## The view of the human in a played match of `render`, or null when none was built. The cone is
## read too: it keeps being published in either mode.
func _view_of(t: TestContext, render: String) -> PlayerView:
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
		return null
	menu.start_requested.emit(SPEC.merged({ "mode": "play" }))
	if not await t.until(func() -> bool: return not Probe.views_under(viewport).is_empty(), 10.0):
		return null
	await t.frames(3)
	var view: PlayerView = Probe.views_under(viewport)[0]
	t.check(view.rebuilds() > 0 or view.starts() > 0, "%s: the cone is still built" % render)
	return view
