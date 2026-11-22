extends GameTest
## An emptied shelf looks as full as the old one from the game camera, in a real window (windowed
## only: the headless renderer draws nothing; #194 unbake-b, D21 "the old look kept",
## `docs/stacked-items.md` SI13). A played 3D match, and beside its district each of the four
## shelves twice, the OLD look (`art_opts.loose` off: the books, boxes and shoes built into one
## mesh) and the EMPTIED one with the same things loose on its boards (`RoomItems.carry`), the
## camera over each in turn: what the shelf holds must read as bright and as filled as the old
## picture (the mean luminance of the shelf's contents in the picture, the emptied one at least
## `MIN_SHARE` of the old) and, for the shoe rack, as shaped (a shoe's toe is wider than its heel:
## the lit pixels of the toe rows over those of the heel rows, at least `MIN_TOE`: shoes
## measure 1.46, a pair drawn as two plain boxes with an opening 1.23). The two shelves of a pair
## stand at the same spot in
## turn, so the same light falls on both. With
## `EMPTIED_SHOT_DIR=<dir>` set it saves a picture of each. Run:
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
## How far apart the shelves of two keys stand, in px (a pair of one key stands at the same spot).
const ROW := 120.0
## The emptied shelf's contents must be at least this share of the old one's brightness.
const MIN_SHARE := 0.8
## A pixel that is part of a shoe is at least this bright (the rack's back and outlines are not).
const SHOE_LIGHT := 0.09
## The heel rows and the toe rows of the shoes in the picture, in px from its middle (the shoes
## lie within the middle 56 px across), and how much wider the toe rows must be than the heel rows
## (the mutant of two plain boxes: 1.23; the shoes: 1.46).
const HEEL_ROWS := Vector2(-8.0, -2.0)
const TOE_ROWS := Vector2(-2.0, 4.5)
const MIN_TOE := 1.35

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
	await t.frames(60)
	var origin := _widest_floor() + Vector2(-450.0, 0.0)
	for i in KEYS.size():
		await _compare(t, KEYS[i], origin + Vector2(0.0, i * ROW))
	await MainProbe.close(t, _window)


## The shelf `key` at `at` old, then emptied at the same spot: as bright and as shaped.
func _compare(t: TestContext, key: String, at: Vector2) -> void:
	var old := _shelf(key, at, false)
	var old_image := await _picture(t, old, key + "_old")
	old.queue_free()
	await t.frames(5)
	var new_image := await _picture(t, _shelf(key, at, true), key + "_emptied")
	var old_light := _contents_light(old_image)
	var new_light := _contents_light(new_image)
	t.check(
		new_light >= old_light * MIN_SHARE,
		"the emptied %s reads as bright as the old (%.3f against %.3f)"
		% [key, new_light, old_light],
	)
	if key == "shoe_rack":
		var toe := _toe_over_heel(new_image)
		t.check(toe >= MIN_TOE, "the emptied shoes have a toe wider than the heel (%.2f)" % toe)


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


## The shelf `key` at `at`: the old look (`loose` off, its things built into one mesh) or the
## emptied one with its things loose on its boards.
func _shelf(key: String, at: Vector2, emptied: bool) -> Node2D:
	var definition := WorldGen.object_definition(key).duplicate(true)
	if not emptied:
		var opts: Dictionary = definition.get("art_opts", {})
		opts["loose"] = false
		definition["art_opts"] = opts
	var piece := ObjectFactory.spawn(definition, at, _world, {})
	if emptied:
		RoomItems.carry(piece, definition, _world, "gallery")
	return piece


## The window's picture with the camera over `piece` (saved when asked to).
func _picture(t: TestContext, piece: Node2D, name_: String) -> Image:
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.global_position = piece.global_position
	await t.frames(20)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("EMPTIED_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, name_])
	return image


## The picture's middle, where the shelf's contents are.
func _contents_area(image: Image) -> Rect2i:
	var centre := Vector2(image.get_size()) * 0.5
	return Rect2i(centre - Vector2(30.0, 12.0) * ZOOM, Vector2(60.0, 24.0) * ZOOM)


## The mean luminance of the middle of the picture, where the shelf's contents are.
func _contents_light(image: Image) -> float:
	var area := _contents_area(image)
	var sum := 0.0
	var count := 0
	for y in range(area.position.y, area.end.y, 2):
		for x in range(area.position.x, area.end.x, 2):
			sum += image.get_pixel(x, y).get_luminance()
			count += 1
	return sum / float(maxi(count, 1))


## The lit pixels of the shoes' toe rows over those of their heel rows (a flat box gives 1.0).
func _toe_over_heel(image: Image) -> float:
	var centre := Vector2(image.get_size()) * 0.5
	var heel := _lit_in(image, centre, HEEL_ROWS)
	var toe := _lit_in(image, centre, TOE_ROWS)
	return float(toe) / float(maxi(heel, 1))


## The pixels of the shoe rows `rows` (px from `centre`, across ±28 px) at least `SHOE_LIGHT`.
func _lit_in(image: Image, centre: Vector2, rows: Vector2) -> int:
	var count := 0
	for y in range(int(centre.y + rows.x * ZOOM), int(centre.y + rows.y * ZOOM)):
		for x in range(int(centre.x - 28.0 * ZOOM), int(centre.x + 28.0 * ZOOM)):
			if image.get_pixel(x, y).get_luminance() >= SHOE_LIGHT:
				count += 1
	return count


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
