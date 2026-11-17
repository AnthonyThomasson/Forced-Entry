extends GameTest
## The wall fade drawn in a real window (windowed only: the headless renderer draws nothing and
## compiles no shader; #193 rule 9, Art's `WallFade`). A played 3D match, the player stood inside
## the house close behind a wall as the camera sees it, at two camera turns, and then the view
## spectating (the camera framing three characters each behind a wall): the picture round the
## wall changes when it fades (the same view with the fade turned off differs), and the log gate
## fails the test on any shader or engine error. With `WALL_FADE_SHOT_DIR=<dir>` set it saves a
## picture of each (`player_yaw0`, `player_yaw0_no_fade`, `player_yaw90`, `spectating`). Run:
## `tools/run_tests.sh --windowed --id=art/wall_fade_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_art/art_wall_fade_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_wall_fade_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 3 },
	"invaders": { "count": 3 },
}
## How far behind the middle of its wall the player stands (just past its face: at the 80 degree
## pitch a 96 px wall hides only what stands within 17 px of it), and how far walls stand apart.
const STANDOFF := 9.0
const APART := 200.0
## The share of the picture that must change between the fade and no fade, with the player at a
## wall: a wall's worth of pixels, a few percent of the window at this zoom.
const MIN_CHANGED := 0.004

var _window: SubViewport
var _main: Node2D
var _player: Node2D
var _camera: Camera2D
var _rig: CameraRig
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "A wall between the camera and the player fades in the picture (windowed)",
		"description": "A played 3D match in a window, the player inside the house behind a wall "
			+ "at two camera turns and the view spectating: the picture differs from the same "
			+ "view with the fade off, and no shader or engine error is logged. Windowed only.",
		"tags": ["render", "3d", "wall-fade", "windowed"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(WallFadeConfig, &"faded_amount", 0.2)
	s.switch(&"vision.enabled", false)  # the whole house in view: the fade is what is judged
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	if not await _start(t):
		return
	var walls := Probe.walls(_main.get_node("View3D").mirror, _world, APART, _inside_house)
	if not t.require(walls.size() >= 3, "the house has three walls to stand behind"):
		return
	var yaw := _rig.yaw
	await _stand_player(t, walls[0], Probe.back_of(yaw))
	var faded := await _shoot(t, "player_yaw%d" % int(yaw))
	WallFadeConfig.faded_amount = 1.0  # a wall "faded" to whole: the same view, no fade
	var whole := await _shoot(t, "player_yaw%d_no_fade" % int(yaw))
	WallFadeConfig.faded_amount = 0.2
	var changed := _share_changed(faded, whole)
	t.check(
		changed >= MIN_CHANGED, "the wall's fade changes the picture (%.2f%%)" % (changed * 100.0)
	)
	_rig.yaw = 90.0
	await _stand_player(t, walls[0], Probe.back_of(90.0))
	await _shoot(t, "player_yaw90")
	await _spectate(t, walls)
	await MainProbe.close(t, _window)


## Main whole in the window, a played 3D match started, the camera on its real controller.
func _start(t: TestContext) -> bool:
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	_main = MainProbe.open(_window)
	MainProbe.setup_menu(_main).queue_free()
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	_main.add_child(_camera)
	_camera.make_current()
	_player = _main.get_node("Player")
	var spec := SPEC.duplicate(true)
	spec["human"] = { "node": _player, "side": &"invader", "lead": false }
	var built: Dictionary = await _main.start_match(spec)
	if not t.require(not built.is_empty(), "a played match started in 3D"):
		return false
	_world = built["world"]
	_rig = _main.get_node("View3D").rig
	await t.frames(30)
	return true


## Whether `centre` (a point on the ground) lies on a floor of the house (not the street).
func _inside_house(centre: Vector2) -> bool:
	for node: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(node) and node.get("art") != "street":
			if Rect2((node as Node2D).global_position, node.get("size")).has_point(centre):
				return true
	return false


## Stand the player behind `wall`'s segment as a camera looking from `back` sees it, the camera
## on the player.
func _stand_player(t: TestContext, wall: Dictionary, back: Vector2) -> void:
	_player.global_position = Probe.behind(wall, back, STANDOFF)
	_camera.global_position = _player.global_position
	_camera.zoom = Vector2(3.0, 3.0)
	_camera.set_process(false)  # stays on the player: no look-ahead toward the mouse
	await t.frames(1)


## Let the picture settle and read it back (saved when asked to).
func _shoot(t: TestContext, shot_name: String) -> Image:
	await t.seconds(0.8)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("WALL_FADE_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, shot_name])
	return image


## The view spectating: three characters, frozen, each behind a wall, framed by the camera.
func _spectate(t: TestContext, walls: Array) -> void:
	var back := Probe.back_of(_rig.yaw)
	var characters: Array[Node2D] = []
	var all := _world.get_tree().get_nodes_in_group(&"characters")
	for i in 3:
		var who := all[i + 1] as Node2D
		who.process_mode = Node.PROCESS_MODE_DISABLED
		who.global_position = Probe.behind(walls[i], back, STANDOFF)
		characters.append(who)
	_camera.set_process(true)
	_camera.call(&"frame", characters)
	await _shoot(t, "spectating")
	for i in 3:
		t.check(
			Probe.level(walls[i]["part"]) < 0.9,
			"spectating: the wall in front of character %d fades (%.2f)"
			% [i, Probe.level(walls[i]["part"])],
		)


## The share of pixels that differ between two pictures.
func _share_changed(a: Image, b: Image) -> float:
	var different := 0
	var samples := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			samples += 1
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				different += 1
	return float(different) / float(maxi(samples, 1))
