extends GameTest
## The domestic furniture of a 3D match in a real window (windowed only: the headless renderer
## draws nothing and compiles no shader; #193 phase 2, Objects). A Watch match started with 3D
## chosen, the camera parked over the living room, bedroom, bathroom and kitchen of the starter
## home, the study of the office loft and the kitchenette of the micro flat, and close on each kind:
## each piece is shown by its kit mesh (Main's view registered the builders), the toon bands,
## outline and glows are in the picture, and the log gate fails the test on any shader or engine
## error. With `FURNITURE_SHOT_DIR=<dir>` set it saves one picture per room;
## `FURNITURE_PITCH=<degrees>`
## tips the camera and `FURNITURE_ZOOM=<z>` sets the room pictures' zoom (the close-ups'
## are 2.5 times it). Run:
## `FURNITURE_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=objects/furniture_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_furniture_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const ZOOM := 1.6
## The close-up of one piece of each kind the match has: the zoom.
const CLOSE_ZOOM := 4.0
## The homes to build, each a floorplan, the rooms of it to photograph (a picture name, the room's
## type and the art of a piece that stands in it) and the kinds to take a close-up of, a piece of
## each.
const HOMES := [
	{
		"plan": "starter_home",
		"rooms": [
			["living_room", "living_room", "sofa"],
			["bedroom", "bedroom", "bed"],
			["bathroom", "bathroom", "bath"],
			["kitchen", "kitchen", "counter"],
		],
		"kinds": [
			"sofa", "chair", "cabinet", "shelf", "counter", "appliance", "bed", "toilet", "bath",
			"rug", "plant", "lamp", "coat_rack", "recliner", "fixture",
		],
	},
	{
		"plan": "office_loft",
		"rooms": [["study", "home_office", "office_chair"]],
		"kinds": ["office_chair"],
	},
	{
		"plan": "micro_flat",
		"rooms": [["kitchenette", "kitchenette", "hotplate"]],
		"kinds": ["hotplate"],
	},
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
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	if OS.get_environment("FURNITURE_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("FURNITURE_PITCH")))
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	for home: Dictionary in HOMES:
		await _photograph(t, home)


## Build the home of `home` in a window of its own and take its pictures.
func _photograph(t: TestContext, home: Dictionary) -> void:
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
	var spec := SPEC.duplicate(true)
	spec["plan"] = home["plan"]
	var built: Dictionary = await main.start_match(spec)
	if not t.require(not built.is_empty(), "a Watch match started in 3D (%s)" % home["plan"]):
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").mirror
	_hide_walls(built["world"])  # full-height walls would stand between the camera and it
	_world = built["world"]
	await _rooms(t, built["rooms"], home["rooms"])
	await _close_ups(t, home["kinds"])
	var alive := ToonMaterial.textured_count()
	print("FURNITURE %s: %d textured materials alive" % [home["plan"], alive])
	await MainProbe.close(t, _window)


## One picture of each of `wanted` rooms, the camera over its middle.
func _rooms(t: TestContext, rooms: Array, wanted: Array) -> void:
	var zoom := _env_zoom(ZOOM)
	_camera.zoom = Vector2(zoom, zoom)
	for room: Array in wanted:
		var rect := _rect_of(rooms, room[1])
		var piece := _first_of(room[2])
		if not t.require(rect.has_area() and piece != null, "the home has a %s" % room[0]):
			continue
		_camera.global_position = rect.get_center()
		await t.frames(20)
		_check_rig(t, piece, "the %s of the %s" % [room[2], room[0]])
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		_save(room[0])


## A close-up of a piece of each of `kinds`.
func _close_ups(t: TestContext, kinds: Array) -> void:
	var zoom := _env_zoom(ZOOM) * CLOSE_ZOOM / ZOOM
	_camera.zoom = Vector2(zoom, zoom)
	for art: String in kinds:
		var piece := _first_of(art)
		if not t.require(piece != null, "the home has a %s" % art):
			continue
		_camera.global_position = piece.global_position
		await t.frames(8)
		_check_rig(t, piece, "a %s" % art)
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		_save("kind_%s" % art)


## The room pictures' zoom: `FURNITURE_ZOOM` when set, else `fallback`.
func _env_zoom(fallback: float) -> float:
	var named := OS.get_environment("FURNITURE_ZOOM")
	return float(named) if named != "" else fallback


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
