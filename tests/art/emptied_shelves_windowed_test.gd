extends GameTest
## An emptied shelf looks as full as the old one from the game camera, in a real window (windowed
## only: the headless renderer draws nothing; #194 unbake-b, D21 "the old look kept",
## `docs/stacked-items.md` SI13). A played 3D match, and beside its district each of the four
## shelves twice, the OLD look (`art_opts.loose` off: the books, boxes and shoes built into one
## mesh) and the EMPTIED one with the same things loose on its boards (`RoomItems.carry`), the
## camera over each in turn: what the shelf holds must read as bright and as filled as the old
## picture (the mean luminance of the shelf's contents in the picture, the emptied one at least
## `MIN_SHARE` of the old). With `EMPTIED_SHOT_DIR=<dir>` set it saves a picture of each. Run:
## `EMPTIED_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=art/emptied_shelves_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_emptied_shelves_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "garage_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const KEYS := ["bookshelf", "shelving", "linen_shelf", "shoe_rack"]
const ZOOM := 3.0
## How far the emptied shelf stands from the old one, in px.
const SIDE := 105.0
## The emptied shelf's contents must be at least this share of the old one's brightness.
const MIN_SHARE := 0.8

var _window: SubViewport
var _camera: Camera2D
var _mirror: MeshCarrier
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "An emptied shelf reads as full as the old one (windowed)",
		"description": "A 3D match in a window, each of the four shelves old (its things built "
			+ "in) and emptied (them loose on the boards) under the game camera: the emptied "
			+ "shelf's contents are as bright as the old one's. Windowed only.",
		"tags": ["render", "3d", "windowed", "furniture", "unbake"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	var built := await _start(t)
	if not t.require(not built.is_empty(), "a match started in 3D"):
		return
	var pairs := _gallery(t)
	await t.frames(60)
	for pair: Array in pairs:
		var key: String = pair[0]
		var image := await _picture(t, pair[1], pair[2], key)
		var old_light := _contents_light(image, -SIDE * 0.5)
		var new_light := _contents_light(image, SIDE * 0.5)
		t.check(
			new_light >= old_light * MIN_SHARE,
			"the emptied %s reads as bright as the old (%.3f against %.3f)"
			% [key, new_light, old_light],
		)
	await MainProbe.close(t, _window)


## Main whole in the window with a played 3D match started and the camera on it: the match built
## (`{}` when it did not start).
func _start(t: TestContext) -> Dictionary:
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
	if built.is_empty():
		return built
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").carrier
	_world = built["world"]
	_hide_walls()
	return built


## Each shelf of `KEYS` twice in a row, old and emptied with its things: `[[key, old, emptied]]`.
func _gallery(_t: TestContext) -> Array:
	var origin := _widest_floor() + Vector2(-450.0, 0.0)
	var pairs: Array = []
	for i in KEYS.size():
		var key: String = KEYS[i]
		var old := WorldGen.object_definition(key).duplicate(true)
		var opts: Dictionary = old.get("art_opts", {})
		opts["loose"] = false
		old["art_opts"] = opts
		var at := origin + Vector2(0.0, i * 120.0)
		var built_old := ObjectFactory.spawn(old, at, _world, {})
		var definition := WorldGen.object_definition(key)
		var emptied := ObjectFactory.spawn(definition, at + Vector2(SIDE, 0.0), _world, {})
		RoomItems.carry(emptied, definition, _world, "gallery")
		pairs.append([key, built_old, emptied])
	return pairs


## The window's picture with the camera between `old` and `emptied` (saved when asked to).
func _picture(t: TestContext, old: Node2D, emptied: Node2D, name_: String) -> Image:
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.global_position = (old.global_position + emptied.global_position) * 0.5
	await t.frames(20)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("EMPTIED_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, name_])
	return image


## The mean luminance of the middle of the shelf `across` px to the side of the picture's centre.
func _contents_light(image: Image, across: float) -> float:
	var centre := Vector2(image.get_size()) * 0.5 + Vector2(across * ZOOM, 0.0)
	var area := Rect2(centre - Vector2(30.0, 12.0) * ZOOM, Vector2(60.0, 24.0) * ZOOM)
	var sum := 0.0
	var count := 0
	for y in range(int(area.position.y), int(area.end.y), 2):
		for x in range(int(area.position.x), int(area.end.x), 2):
			sum += image.get_pixel(x, y).get_luminance()
			count += 1
	return sum / float(maxi(count, 1))


## The middle of the largest floor of the house, where the dusk lights it.
func _widest_floor() -> Vector2:
	var best := Rect2()
	for node: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			if rect.get_area() > best.get_area():
				best = rect
	return best.get_center()


## Hide the proxies of every wall: the picture shows what stands inside the rooms.
func _hide_walls() -> void:
	for body: Node in PlanProbe.bodies_under(_world):
		if MeshKinds.kind_of(body) == MeshKinds.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false
