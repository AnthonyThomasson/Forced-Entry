extends GameTest
## A table of a 3D match in a real window (windowed only: the headless renderer draws nothing and
## compiles no shader; #193 phase 2, Objects). A Watch match started with 3D chosen, the camera
## parked over a table the match built and zoomed in: the table is shown by the mesh kit's top
## over four legs (Main's view registered the builder), the legs' shadow tone and the toon bands
## are in the picture, and the log gate fails the test on any shader or engine error. With
## `MESHKIT_SHOT=<file.png>` set it saves the picture. Run:
## `tools/run_tests.sh --windowed --id=objects/table_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_table_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const ZOOM := 2.2


func describe() -> Dictionary:
	return {
		"name": "A kit-built table draws in a 3D match without shader or engine errors (windowed)",
		"description": "A 3D Watch match, the camera over one of its tables: the mirror shows it "
			+ "by the kit's mesh and the picture around it is drawn. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit"],
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
	var table := _first_table(built["world"])
	if not t.require(table != null, "the match has a table"):
		return
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.zoom = Vector2(ZOOM, ZOOM)
	camera.global_position = table.global_position
	await t.frames(40)
	var view: Node = main.get_node("View3D")
	var mirror: WorldMirror = view.mirror
	_hide_walls(built["world"], mirror)  # full-height walls would stand between the camera and it
	var shown := mirror.proxies_of(table)
	var kit_mesh: bool = shown.size() == 1 and shown[0] is FurnitureRig
	if kit_mesh:
		kit_mesh = not (shown[0] as FurnitureRig).body.mesh is BoxMesh
	t.check(kit_mesh, "the table is shown by a mesh of the kit, not its proxy box")
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var shot := OS.get_environment("MESHKIT_SHOT")
	if shot != "":
		window.get_texture().get_image().save_png(shot)
	await MainProbe.close(t, window)


## Hide the proxies of every wall, so the picture shows what stands inside the rooms (the walls
## fade round the player only in the wall-fade job).
func _hide_walls(world: Node, mirror: WorldMirror) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		if MirrorProxy.kind_of(body) == MirrorProxy.WALL:
			for proxy in mirror.proxies_of(body):
				proxy.visible = false


## The first piece the match built that is painted as a table.
func _first_table(world: Node) -> Node2D:
	for body: Node in world.find_children("*", "RigidBody2D", true, false):
		var look: Variant = body.get("look")
		if look is Object and (look as Object).get("art") == "table":
			return body as Node2D
	return null
