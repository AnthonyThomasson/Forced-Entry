extends GameTest
## A car and a van of a 3D match in a real window (windowed only: the headless renderer draws
## nothing and compiles no shader; #193 phase 2, Vehicles). A Watch match started with 3D chosen, a
## car and a van set down on a room's floor under the camera: both are shown by the kit's meshes
## (Main's view registered the builder), a door opens, the car brakes and takes a hit, and the log
## gate fails the test on any shader or engine error. With `VEHICLE_SHOT_DIR=<dir>` set it saves the
## pictures
## there (the car shut, the car with a door open braking and dented, the van with its doors open,
## both seen from another side; `VEHICLE_ZOOM=<n>` and `VEHICLE_PITCH=<degrees>` set the
## camera). Run:
## `VEHICLE_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=vehicle/vehicle_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const CarScene := preload("res://scenes/vehicle/car.tscn")
const VanScene := preload("res://scenes/vehicle/van.tscn")
const SCRATCH := "user://settings_vehicle_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 1 },
	"invaders": { "count": 1 },
}
const ZOOM := 1.6  # `VEHICLE_ZOOM=<n>` overrides it


func describe() -> Dictionary:
	return {
		"name": "A kit-built car and van draw in a 3D match without errors (windowed)",
		"description": "A 3D Watch match with a car and a van on a floor under the camera: the "
			+ "mirror shows them by the kit's meshes, a door opens, the car brakes and is hit, "
			+ "and the picture is drawn. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "vehicle"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	if OS.get_environment("VEHICLE_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("VEHICLE_PITCH")))
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
	var vehicles := await _park(t, main, camera, built["world"])
	var view: Node = main.get_node("View3D")
	for body in vehicles:
		var shown: Array = view.mirror.proxies_of(body)
		t.check(
			shown.size() == 1 and shown[0] is VehicleMeshRig,
			"%s is shown by a mesh of the kit, not its proxy box" % body.name,
		)
	await _shot(t, window, "1_car_shut")
	await _open_and_dent(t, vehicles[0], vehicles[1])
	await _shot(t, window, "2_car_open_braking_dented")
	view.rig.yaw += 110.0
	await t.frames(10)
	await _shot(t, window, "3_turned")
	view.rig.yaw -= 220.0
	await t.frames(10)
	await _shot(t, window, "4_turned_other_way")
	# the dents hidden: whatever dark marks remain on the road are not patches
	for body in vehicles:
		for patch in view.mirror.proxies_of(body)[0].patches:
			patch.visible = false
	await _shot(t, window, "5_patches_hidden")
	await MainProbe.close(t, window)


## A car and a van set down on the largest floor under the camera, zoomed in, the walls and what
## stands near them hidden: the two vehicles.
func _park(t: TestContext, main: Node, camera: Camera2D, world: Node) -> Array[RigidBody2D]:
	var spot := _open_floor(world)
	var car := CarScene.instantiate() as RigidBody2D
	var van := VanScene.instantiate() as RigidBody2D
	car.position = spot + Vector2(-130, -80)
	van.position = spot + Vector2(150, 110)
	world.add_child(car)
	world.add_child(van)
	camera.set_process(false)
	camera.set_physics_process(false)
	var zoom := ZOOM
	if OS.get_environment("VEHICLE_ZOOM") != "":
		zoom = float(OS.get_environment("VEHICLE_ZOOM"))
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = spot
	await t.frames(40)
	var mirror: WorldMirror = main.get_node("View3D").mirror
	_hide_walls(world, mirror)  # full-height walls would stand between the camera and them
	_hide_clutter(world, mirror, spot)
	return [car, van]


## Open the car's front door and the van's side and rear doors, brake, and hit the car's side.
func _open_and_dent(t: TestContext, car: RigidBody2D, van: RigidBody2D) -> void:
	car.cabin.door(&"front_left").open()
	car.cabin.door(&"rear_right").open()
	for id in [&"side", &"rear_left", &"front_right"]:
		van.cabin.door(id).open()
	for i in 3:
		var hit := HitInfo.new()
		hit.position = car.to_global(Vector2(-10.0 * i, 55.0))
		hit.normal = Vector2.DOWN
		hit.direction = Vector2.UP
		hit.damage = 25.0
		car.take_hit(hit)
	car.drive.braking = true
	await t.frames(40)


## The picture, saved when `VEHICLE_SHOT_DIR` names a folder.
func _shot(t: TestContext, window: SubViewport, name: String) -> void:
	await t.frames(5)
	# A window the desktop covers is not drawn and never signals frame_post_draw: draw the viewport
	# on demand (synchronously) and read it back at once.
	RenderingServer.force_draw(false)
	var dir := OS.get_environment("VEHICLE_SHOT_DIR")
	if dir != "":
		window.get_texture().get_image().save_png("%s/%s.png" % [dir, name])


## The middle of the largest floor the match built (where a vehicle has room).
func _open_floor(world: Node) -> Vector2:
	var best := Vector2.ZERO
	var best_area := 0.0
	for floor_node in world.get_tree().get_nodes_in_group(&"floors"):
		var node := floor_node as Node2D
		var size: Variant = node.get("size")
		if (node != null
				and size is Vector2
				and (size as Vector2).x * (size as Vector2).y > best_area):
			best_area = (size as Vector2).x * (size as Vector2).y
			best = node.global_position + (size as Vector2) * 0.5
	return best if best_area > 0.0 else world.get_child(0).global_position


## Hide the proxies of every wall, so the picture shows what stands inside the rooms (the walls
## fade round the player only in the wall-fade job).
func _hide_walls(world: Node, mirror: WorldMirror) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		if MirrorProxy.kind_of(body) == MirrorProxy.WALL:
			for proxy in mirror.proxies_of(body):
				proxy.visible = false


## Hide furniture and characters near `at`, so the vehicles stand clear in the picture.
func _hide_clutter(world: Node, mirror: WorldMirror, at: Vector2) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		var node := body as Node2D
		if node.global_position.distance_to(at) < 450.0 and not node.is_in_group(&"vehicles"):
			if MirrorProxy.kind_of(body) != MirrorProxy.WALL:
				for proxy in mirror.proxies_of(body):
					proxy.visible = false
