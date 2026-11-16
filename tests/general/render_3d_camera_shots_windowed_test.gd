extends GameTest
## The near top-down 3D camera drawn in a real window (windowed only: the headless renderer draws
## nothing and compiles no shader; #193 phase 2b, General). A Watch match started with 3D chosen,
## the camera parked over the street and over the house at the zoom steps 1x, 2x and 3x and the
## camera at north (yaw 0) and east (yaw 90): the picture is drawn without shader or engine errors,
## the rig's picture pixel is the zoom's whole screen pixels at each step, and the rig rests on the
## cardinal. With `CAMERA_SHOT_DIR=<dir>` set it saves a picture of each (`street_z1_yaw0` ...).
## Run: `tools/run_tests.sh --windowed --id=general/render_3d_camera_shots_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_render_3d_camera_shots_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const ZOOMS := [1.0, 2.0, 3.0]
const YAWS := [0.0, 90.0]

var _window: SubViewport
var _rig: CameraRig


func describe() -> Dictionary:
	return {
		"name": "The near top-down camera draws the street and a house at 1x to 3x (windowed)",
		"description": "A 3D Watch match, the camera over the street and the house at zoom 1, 2 "
			+ "and 3 and yaw 0 and 90: drawn without shader or engine errors, a picture pixel the "
			+ "zoom's whole screen pixels. Windowed only.",
		"tags": ["render", "3d", "camera", "windowed"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.switch(&"vision.enabled", false)  # the whole street and house in view
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	var main := MainProbe.open(_window)
	MainProbe.setup_menu(main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.set_script(CameraScript)
	main.add_child(camera)
	camera.make_current()
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	camera.set_process(false)
	camera.set_physics_process(false)
	var world: Node = built["world"]
	_rig = main.get_node("View3D").rig
	await t.frames(30)
	var spots := {
		"street": _street_spot(world),
		"house": _house_centre(world),
	}
	for place: String in spots:
		for zoom: float in ZOOMS:
			for yaw: float in YAWS:
				_rig.yaw = yaw
				await _shoot(
					t,
					camera,
					spots[place],
					zoom,
					"%s_z%d_yaw%d" % [place, zoom, yaw],
				)
	await MainProbe.close(t, _window)


## Park the camera over `at` at `zoom`, wait for the picture, check the rig and save it when asked.
func _shoot(
	t: TestContext, camera: Camera2D, at: Vector2, zoom: float, shot_name: String
) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = at
	await t.frames(20)
	# A window the desktop covers is not drawn and never signals frame_post_draw: draw the viewport
	# on demand (synchronously) and read it back at once.
	RenderingServer.force_draw(false)
	t.expect_near(
		_rig.texel(),
		RenderConfig.art_pixel * RenderConfig.unit,
		0.001,
		"%s: one art pixel" % shot_name,
	)
	var dir := OS.get_environment("CAMERA_SHOT_DIR")
	if dir != "":
		_window.get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


## The middle of the first road or pavement of the match's street.
func _street_spot(world: Node) -> Vector2:
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node) and node.get("art") == "street":
			return (node as Node2D).global_position + Vector2(node.get("size")) * 0.5
	return Vector2.ZERO


## The middle of the match's house floors (the street is not part of it).
func _house_centre(world: Node) -> Vector2:
	var bounds := Rect2()
	var first := true
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			bounds = rect if first else bounds.merge(rect)
			first = false
	return bounds.get_center()
