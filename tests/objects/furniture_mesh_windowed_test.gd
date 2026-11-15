extends GameTest
## The domestic furniture of a 3D match in a real window (windowed only: the headless renderer
## draws nothing and compiles no shader; #193 phase 2, Objects). A Watch match started with 3D
## chosen, the camera parked over the living room, bedroom, bathroom and kitchen of the starter
## home the match built: each piece is shown by its kit mesh (Main's view registered the
## builders), the toon bands, outline and glows are in the picture, and the log gate fails the test
## on any shader or engine error. With `FURNITURE_SHOT_DIR=<dir>` set it saves one picture per room.
## Run:
## `FURNITURE_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=objects/furniture_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_furniture_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "starter_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const ZOOM := 1.6
## The close-up of one piece of each kind the match has: the zoom.
const CLOSE_ZOOM := 4.0
const KINDS := [
	"sofa", "chair", "cabinet", "shelf", "counter", "appliance", "bed", "office_chair", "toilet",
	"bath", "rug", "plant", "lamp", "coat_rack", "recliner", "fixture", "hotplate",
]
## The rooms of the starter home to photograph: a picture name, the room's type and the art of a
## piece that stands in it.
const ROOMS := [
	["living_room", "living_room", "sofa"],
	["bedroom", "bedroom", "bed"],
	["bathroom", "bathroom", "bath"],
	["kitchen", "kitchen", "counter"],
]

var _window: SubViewport
var _camera: Camera2D
var _mirror: WorldMirror
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "Furnished rooms draw in a 3D match without shader or engine errors (windowed)",
		"description": "A 3D Watch match in the starter home, the camera over its living room, "
			+ "bedroom, bathroom and kitchen: the furniture is shown by its kit meshes and "
			+ "the pictures are drawn. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "furniture"],
		"timeout": 150.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
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
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	main.add_child(_camera)
	_camera.make_current()
	var built: Dictionary = await main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").mirror
	_hide_walls(built["world"])  # full-height walls would stand between the camera and it
	_world = built["world"]
	await _rooms(t, built["rooms"])
	await _close_ups(t)
	await MainProbe.close(t, _window)


## One picture of each room of the starter home, the camera over its middle.
func _rooms(t: TestContext, rooms: Array) -> void:
	_camera.zoom = Vector2(ZOOM, ZOOM)
	var shown := 0
	for room: Array in ROOMS:
		var rect := _rect_of(rooms, room[1])
		var piece := _first_of(room[2])
		if not t.require(rect.has_area() and piece != null, "the home has a %s" % room[0]):
			continue
		_camera.global_position = rect.get_center()
		await t.frames(20)
		_check_rig(t, piece, "the %s of the %s" % [room[2], room[0]])
		await RenderingServer.frame_post_draw
		_save(room[0])
		shown += 1
	t.expect_eq(shown, ROOMS.size(), "every room was photographed")


## A close-up of a piece of each kind the match has.
func _close_ups(t: TestContext) -> void:
	_camera.zoom = Vector2(CLOSE_ZOOM, CLOSE_ZOOM)
	for art: String in KINDS:
		var piece := _first_of(art)
		if piece == null:
			continue
		_camera.global_position = piece.global_position
		await t.frames(8)
		_check_rig(t, piece, "a %s" % art)
		await RenderingServer.frame_post_draw
		_save("kind_%s" % art)


## `piece` is shown by a furniture rig, not its proxy box.
func _check_rig(t: TestContext, piece: Node2D, what: String) -> void:
	var rigs := _mirror.proxies_of(piece)
	t.check(rigs.size() == 1 and rigs[0] is FurnitureRig, "%s is shown by a furniture rig" % what)


## The world rectangle of the first of `rooms` of `type` (empty for none).
func _rect_of(rooms: Array, type: String) -> Rect2:
	for room: Dictionary in rooms:
		if room["type"] == type:
			return room["rect"]
	return Rect2()


## Save the window's picture as `<FURNITURE_SHOT_DIR>/<name>.png` when the directory is named.
func _save(picture: String) -> void:
	var dir := OS.get_environment("FURNITURE_SHOT_DIR")
	if dir != "":
		_window.get_texture().get_image().save_png("%s/%s.png" % [dir, picture])


## Hide the proxies of every wall, so the picture shows what stands inside the rooms (the walls
## fade round the player only in the wall-fade job).
func _hide_walls(world: Node) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		if MirrorProxy.kind_of(body) == MirrorProxy.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false


## The first piece the match built that is painted as `art`.
func _first_of(art: String) -> Node2D:
	for body: Node in _world.find_children("*", "RigidBody2D", true, false):
		var look: Variant = body.get("look")
		if look is Object and (look as Object).get("art") == art:
			return body as Node2D
	return null
