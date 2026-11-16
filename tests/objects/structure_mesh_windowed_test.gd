extends GameTest
## The building's structure of a 3D match in a real window (windowed only: the headless renderer
## draws nothing and compiles no shader; #193 phase 2, Objects). A Watch match started with 3D
## chosen, the camera parked over a doorway, the street and the whole house in turn (the house again
## at four more camera turns): walls, doors, floors and the street are shown by the mesh kit
## (Main's view registered the builders) and the log gate fails the test on any shader or engine
## error. With `STRUCTURE_SHOT_DIR=<dir>` set it saves a picture of each, and at zoom 1 and 3 of the
## doorway, the street and the house (`STRUCTURE_PITCH=<degrees>` tips the camera,
## `STRUCTURE_ZOOMS_ONLY=1` takes just those (`=house`: just the house's; `STRUCTURE_ZOOM=3` one
## zoom), `STRUCTURE_BROKEN_ONLY=1` just the shattered glass door at the doorway, `=down` just it
## knocked down). Run: `tools/run_tests.sh --windowed --id=objects/structure_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_structure_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}

## The window the match is drawn in.
var window: SubViewport


func describe() -> Dictionary:
	return {
		"name": "Kit-built walls, doors, floors and street draw in a 3D match (windowed)",
		"description": "A 3D Watch match, the camera over a doorway, the street and the house: the "
			+ "mirror shows the structure by the kit's meshes and the picture is drawn without "
			+ "shader or engine errors. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "walls", "doors"],
		"timeout": 400.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	if OS.get_environment("STRUCTURE_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("STRUCTURE_PITCH")))
	s.switch(&"vision.enabled", false)  # the whole street and house in view
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	window = SubViewport.new()
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
	var world: Node = built["world"]
	var mirror: WorldMirror = main.get_node("View3D").mirror
	await t.frames(30)
	var door := _first_door(world)
	if (OS.get_environment("STRUCTURE_BROKEN_ONLY") != ""
			or OS.get_environment("STRUCTURE_ZOOMS_ONLY") != ""):
		await _picked_shots(t, camera, world, door)
		await MainProbe.close(t, window)
		return
	if t.require(door != null, "the match has a house door"):
		_check_door(t, mirror, door)
		await _shoot(t, camera, door.global_position, 2.4, "doorway")
	var street := _first_street(world)
	if t.require(street != null, "the match has a street"):
		await _shoot(t, camera, street.global_position + street.size * 0.5, 1.6, "street")
	var centre := _centre_of_floors(world)
	await _shoot(t, camera, centre, 1.0, "house")
	await _zoom_shots(t, camera, door, street, centre)
	await _broken_glass_shot(t, camera, door)
	# Turn the camera over the house: the floor slabs lie inside the district's pavement slab, and
	# a coplanar top would speckle as the view turns (a picture at each yaw shows none).
	var rig: CameraRig = main.get_node("View3D").rig
	for yaw in [100.0, 160.0, 225.0, 300.0]:
		rig.yaw = yaw
		await _shoot(t, camera, centre, 2.0, "house_yaw%d" % int(yaw))
	await MainProbe.close(t, window)


## The shots a run picked by `STRUCTURE_BROKEN_ONLY` (just the shattered glass door) or
## `STRUCTURE_ZOOMS_ONLY` (the zoom steps, then that door).
func _picked_shots(t: TestContext, camera: Camera2D, world: Node, door: Node2D) -> void:
	if OS.get_environment("STRUCTURE_BROKEN_ONLY") == "":
		await _zoom_shots(t, camera, door, _first_street(world), _centre_of_floors(world))
	if OS.get_environment("STRUCTURE_ZOOMS_ONLY") != "house":
		await _broken_glass_shot(t, camera, door)


## The doorway, the street and the house at zoom 1 and 3 (the 3D render's whole zoom steps).
func _zoom_shots(
	t: TestContext,
	camera: Camera2D,
	door: Node2D,
	street: Node2D,
	centre: Vector2,
) -> void:
	var only := OS.get_environment("STRUCTURE_ZOOM")
	for zoom in [1.0, 3.0]:
		if only != "" and float(only) != zoom:
			continue
		var tag := "z%d" % int(zoom)
		var house_only := OS.get_environment("STRUCTURE_ZOOMS_ONLY") == "house"
		if door != null and not house_only:
			await _shoot(t, camera, door.global_position, zoom, "doorway_" + tag)
		if street != null and not house_only:
			var middle: Vector2 = street.global_position + (street.get("size") as Vector2) * 0.5
			await _shoot(t, camera, middle, zoom, "street_" + tag)
		await _shoot(t, camera, centre, zoom, "house_" + tag)


## The doorway's door made a glass door with its panes shattered (the floor shows through the
## empty panes), at zoom 3 and then knocked down (its slab is the frame and bars).
func _broken_glass_shot(t: TestContext, camera: Camera2D, door: Node2D) -> void:
	if door == null:
		return
	door.look.material = "glass"
	door.look.style = "panes"
	door.look.broken = true
	door.visuals.refresh()
	var only_down := OS.get_environment("STRUCTURE_BROKEN_ONLY") == "down"
	if not only_down:
		await _shoot(t, camera, door.global_position, 3.0, "doorway_broken_glass")
	door.take_damage(10_000.0)
	await _shoot(t, camera, door.global_position, 3.0, "doorway_broken_glass_down")


## The door is shown by its own mesh.
func _check_door(t: TestContext, mirror: WorldMirror, door: Node) -> void:
	var shown := mirror.proxies_of(door)
	t.check(not shown.is_empty() and shown[0] is DoorMesh, "the door is shown by a DoorMesh")


## Park the camera over `at` at `zoom`, wait for the picture and save it as `name` when asked to.
func _shoot(
	t: TestContext,
	camera: Camera2D,
	at: Vector2,
	zoom: float,
	shot_name: String,
) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = at
	await t.frames(20)
	# A window the desktop covers is not drawn and never signals frame_post_draw: draw the viewport
	# on demand (synchronously) and read it back at once.
	RenderingServer.force_draw(false)
	var dir := OS.get_environment("STRUCTURE_SHOT_DIR")
	if dir != "":
		window.get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


## The first house door of the match.
func _first_door(world: Node) -> Node2D:
	for node: Node in world.get_tree().get_nodes_in_group(&"doors"):
		if world.is_ancestor_of(node):
			return node as Node2D
	return null


## The first road or pavement of the match's street.
func _first_street(world: Node) -> Node2D:
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node) and node.get("art") == "street":
			return node as Node2D
	return null


## The middle of the match's house floors (the street is not part of it).
func _centre_of_floors(world: Node) -> Vector2:
	var bounds := Rect2()
	var first := true
	for node: Node in world.get_tree().get_nodes_in_group(&"floors"):
		if world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			bounds = rect if first else bounds.merge(rect)
			first = false
	return bounds.get_center()
