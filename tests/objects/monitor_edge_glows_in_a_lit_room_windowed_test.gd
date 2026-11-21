extends GameTest
## The monitor item's lit edge reads in a lit house room (#194 unbake-a, D21 'the old look kept';
## windowed only: the headless renderer draws nothing). A 3D Watch match in the office loft (seed
## 2), the camera close over the monitor on the desk: the room's dusk and fixtures light the scene,
## and the screen's front edge must still show its own colour (the cheap screen's green, or the
## desk's neon), as the old prop's glowing bar did. A painted, non-emissive edge goes dull brown
## under the room's light; an emissive glow node does not. The same in an unlit arena is no proof.
## Environment: `MONITOR_SHOT=<file.png>` saves the picture. Run:
## `tools/run_tests.sh --windowed --jobs=1 --id=objects/monitor_edge_glows_in_a_lit_room_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const Decay := preload("res://scenes/objects/art/decay.gd")
const SCRATCH :="user://settings_monitor_edge_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "office_loft",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const ZOOMS: Array[float] = [2.5, 6.0]
## How far (0 to 1, per channel) a pixel may stand from the edge's colour to count as it.
const NEAR := 0.3
## The pixels of the edge's colour the picture must hold at least, per zoom 1 of the camera.
const MIN_PIXELS := 12

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "A monitor's lit edge shows its colour in a lit house room (windowed)",
		"description": "The office loft's desk monitor under the room's own light: its screen's "
			+ "front edge is its glow colour in the picture, not a dull painted stripe. Windowed.",
		"tags": ["render", "3d", "windowed", "items", "unbake"],
		"timeout": 90.0,
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
	var window := SubViewport.new()
	window.size = SIZE
	window.world_2d = World2D.new()
	window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(window)
	var main := MainProbe.open(window)
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
	await t.frames(30)
	_mirror = main.get_node("View3D").carrier
	_hide_walls(built["world"])
	var monitor := _monitor(built["world"])
	if not t.require(monitor != null, "the office loft's desk carries a monitor"):
		return
	var edge := Decay.screen_color(monitor.look.art_opts)
	for zoom in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = monitor.global_position
		await t.frames(20)
		RenderingServer.force_draw(false)  # on demand: a covered window never draws
		var picture := window.get_texture().get_image()
		_save(picture, zoom)
		var found := _pixels_near(picture, edge)
		t.check(
			found >= MIN_PIXELS,
			"zoom %.1f: the edge shows its colour %s (%d pixels)" % [
				zoom,
				edge.to_html(false),
				found,
			],
		)
	await MainProbe.close(t, window)


## How many pixels round the middle of `picture` stand within `NEAR` of `colour`, hue and
## brightness: a lit edge is its colour, a painted one is dull.
func _pixels_near(picture: Image, colour: Color) -> int:
	var count := 0
	var middle := Vector2i(picture.get_size() / 2)
	for y in range(middle.y - 100, middle.y + 100):
		for x in range(middle.x - 160, middle.x + 160):
			var p := picture.get_pixel(x, y)
			if (
				absf(p.r - colour.r) < NEAR
				and absf(p.g - colour.g) < NEAR
				and absf(p.b - colour.b) < NEAR
			):
				count += 1
	return count


## Save the picture as `MONITOR_SHOT` (a zoom's suffix) when it names a file.
func _save(picture: Image, zoom: float) -> void:
	var file := OS.get_environment("MONITOR_SHOT")
	if file != "":
		picture.save_png(file.replace(".png", "_%d.png" % int(zoom * 10.0)))


## The first monitor item the match built.
func _monitor(world: Node) -> Node2D:
	for body: Node in PlanProbe.pieces_under(world):
		var look: Variant = body.get("look")
		if look is Object and (look as Object).get("art") == "item":
			var opts: Dictionary = (look as Object).get("art_opts")
			if opts.get("kind") == "monitor":
				return body as Node2D
	return null


## Hide the proxies of every wall, so the picture shows what stands inside the rooms.
func _hide_walls(world: Node) -> void:
	for body: Node in PlanProbe.bodies_under(world):
		if MeshKinds.kind_of(body) == MeshKinds.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false
