extends GameTest
## The bodies of a 3D match in a real window (windowed only: the headless renderer draws nothing and
## compiles no shader; #193 phase 2, Character). A Watch match started with 3D chosen, the camera
## over one of its characters, zoomed in: the character is shown by the kit's body (Main's view
## registered the builder), the picture is drawn, and the log gate fails the test on any shader or
## engine error. The look itself is not asserted: with `CHARMESH_SHOTS=<dir>` set it saves a
## picture of the body standing, crouched and fallen at zoom 3 and at 1 (the game's default), for
## the phase gate (`CHARMESH_PITCH=<degrees>` tips the camera; `CHARMESH_MODE=2d` draws the match
## in 2D and saves only the standing shots: the 2D art to compare the body against). Run:
## `tools/run_tests.sh --windowed --id=character/character_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_character_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## The two zooms of the shots: close, and the game's default (`CameraRig` follows the 2D camera's).
const ZOOMS := [3.0, 1.0]


func describe() -> Dictionary:
	return {
		"name": "A 3D match shows its characters as kit bodies without shader errors (windowed)",
		"description": "A 3D Watch match, the camera over one of its characters, standing and "
			+ "then crouched: the mirror shows it by the body and the picture is drawn. Windowed "
			+ "only.",
		"tags": ["render", "3d", "windowed", "meshkit", "character"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	var two_d := OS.get_environment("CHARMESH_MODE") == "2d"  # the reference shots of the 2D art
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D if two_d else Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	if OS.get_environment("CHARMESH_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("CHARMESH_PITCH")))
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
	var character := _first_character(built["world"])
	if not t.require(character != null, "the match has a living character"):
		return
	camera.set_process(false)
	camera.set_physics_process(false)
	await t.frames(30)
	if OS.get_environment("CHARMESH_MODE") == "2d":
		await _reference(t, window, camera, built["world"], character)
		return
	var mirror: WorldMirror = main.get_node("View3D").mirror
	_hide_walls(built["world"], mirror)  # full-height walls would stand between the camera and it
	var shown := mirror.proxies_of(character)
	t.check(
		shown.size() == 1 and shown[0] is BodyMesh,
		"the character is shown by the kit's body, not its capsule",
	)
	_send_others_away(built["world"], character)
	await _shoot_standing(t, window, camera, character)
	character.movement.set_posture(&"crouch")
	await t.seconds(0.8)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		await _shoot(t, window, camera, character, "crouched_zoom%d" % int(zoom))
	character.movement.set_posture(&"stand")
	character.take_damage(1000.0)
	await t.seconds(2.5)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		await _shoot(t, window, camera, character, "fallen_zoom%d" % int(zoom))
	await MainProbe.close(t, window)


## The 2D match's standing shots (`CHARMESH_MODE=2d`): the art the body is compared against.
func _reference(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	world: Node,
	character: Node2D,
) -> void:
	_send_others_away(world, character)
	await _shoot_standing(t, window, camera, character)
	await MainProbe.close(t, window)


## The standing shots, facing the camera and away from it, at each zoom. Its brain off, the
## character stands and looks where the shot says: toward the camera (the shots' south edge) so the
## face reads.
func _shoot_standing(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
) -> void:
	character.movement.controller = null
	character.movement.move_input = Vector2.ZERO
	for look: String in ["", "_away"]:
		var toward := Vector2(1, 1) if look == "" else Vector2(-1, -1)
		character.movement.aim_point = character.global_position + toward * 200.0
		await t.seconds(0.6)
		for zoom: float in ZOOMS:
			camera.zoom = Vector2(zoom, zoom)
			await _shoot(t, window, camera, character, "standing%s_zoom%d" % [look, int(zoom)])
	character.movement.aim_point = character.global_position + Vector2(200.0, 200.0)


## Park the camera over `character` and save the picture as `<name>.png` in the folder
## `CHARMESH_SHOTS` names (nothing when it is unset).
func _shoot(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
	name: String,
) -> void:
	camera.global_position = character.global_position
	await t.frames(8)
	await RenderingServer.frame_post_draw
	var folder := OS.get_environment("CHARMESH_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		window.get_texture().get_image().save_png("%s/%s.png" % [folder, name])


## Hide the proxies of every wall, so the picture shows what stands inside the rooms (the walls
## fade round the player only in the wall-fade job).
func _hide_walls(world: Node, mirror: WorldMirror) -> void:
	for body: Node in world.find_children("*", "PhysicsBody2D", true, false):
		if MirrorProxy.kind_of(body) in [MirrorProxy.WALL, MirrorProxy.DOOR]:
			for proxy in mirror.proxies_of(body):
				proxy.visible = false


## The first living character the match built.
func _first_character(world: Node) -> CharacterBody2D:
	for body: Node in world.find_children("*", "CharacterBody2D", true, false):
		if not body.get("is_dead"):
			return body as CharacterBody2D
	return null


## The other characters moved far off, so a picture of `character` shows it alone.
func _send_others_away(world: Node, character: Node2D) -> void:
	for body: Node in world.find_children("*", "CharacterBody2D", true, false):
		if body != character:
			(body as Node2D).global_position = Vector2(-6000.0, -6000.0)
