extends GameTest
## The bodies of a 3D match in a real window (windowed only: the headless renderer draws nothing and
## compiles no shader; #193 phase 2, Character). A Watch match, the camera
## over one of its characters, zoomed in: the character is shown by the kit's body (Main's view
## registered the builder), the picture is drawn, and the log gate fails the test on any shader or
## engine error. The look itself is not asserted: with `CHARMESH_SHOTS=<dir>` set it saves a
## picture of the body standing, helmeted, aiming, walking, crouched and fallen at zoom 3 and at 1
## (the game's default), for the phase gate (`CHARMESH_PITCH=<degrees>` tips the camera). Run:
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

## What a shot is taken with: the window, the match's root and the character (set by `run`).
var _window: SubViewport
var _main: Node
var _character: CharacterBody2D


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
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
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
	var built := await _start(t)
	if built.is_empty():
		return
	_send_others_away(built["world"], _character)
	var mirror: WorldMirror = _main.get_node("View3D").mirror
	_hide_walls(built["world"], mirror)  # full-height walls would stand between the camera and it
	var shown := mirror.proxies_of(_character)
	t.check(
		shown.size() == 1 and shown[0] is BodyMesh,
		"the character is shown by the kit's body, not its capsule",
	)
	await _shoot_standing(t)
	await _shoot_dressed(t)
	await _shoot_aiming(t)
	await _shoot_walking(t)
	_character.movement.set_posture(&"crouch")
	await t.seconds(0.8)
	await _shoot_zooms(t, "crouched")
	_character.movement.set_posture(&"stand")
	_character.health = 1.0
	_character.take_damage(1000.0)
	await t.seconds(2.5)
	await _shoot_zooms(t, "fallen")
	await MainProbe.close(t, _window)


## Open the window and the match; its build (empty when the match did not start or has no living
## character), with `_character` set.
func _start(t: TestContext) -> Dictionary:
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	_main = MainProbe.open(_window)
	MainProbe.setup_menu(_main).queue_free()
	var camera := Camera2D.new()
	camera.name = "MainCamera"
	camera.set_script(CameraScript)
	_main.add_child(camera)
	camera.make_current()
	var built: Dictionary = await _main.start_match(SPEC.duplicate(true))
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return {}
	_character = _first_character(built["world"])
	if not t.require(_character != null, "the match has a living character"):
		return {}
	_character.health = 1.0e9  # nobody shoots it while the shots are taken
	camera.set_process(false)
	camera.set_physics_process(false)
	await t.frames(30)
	return built


## The standing shots, facing the camera and away from it, at each zoom. Its brain off, the
## character stands and looks where the shot says: toward the camera (the shots' south edge) so the
## face reads.
func _shoot_standing(t: TestContext) -> void:
	_character.movement.controller = null
	_character.movement.move_input = Vector2.ZERO
	for look: String in ["", "_away"]:
		var toward := Vector2(1, 1) if look == "" else Vector2(-1, -1)
		_character.movement.aim_point = _character.global_position + toward * 200.0
		await t.seconds(0.6)
		await _shoot_zooms(t, "standing%s" % look)
	_character.movement.aim_point = _character.global_position + Vector2(200.0, 200.0)


## The character in a helmet and a plate carrier, facing the camera and away from it: a covered
## head and a vest (the brim and the shell lie past the head's dome, the sprite over the crown
## carries them).
func _shoot_dressed(t: TestContext) -> void:
	var wardrobe: CharacterWardrobe = _character.wardrobe
	var worn: Dictionary = wardrobe.outfit.ids().duplicate()
	wardrobe.outfit.set_ids({
		"head": &"helmet", "vest": &"plate_carrier", "front_plate": &"ceramic_iv", "body": &"shirt",
	})
	for look: String in ["", "_away"]:
		var toward := Vector2(1, 1) if look == "" else Vector2(-1, -1)
		_character.movement.aim_point = _character.global_position + toward * 200.0
		await t.seconds(0.6)
		await _shoot_zooms(t, "helmet%s" % look)
	wardrobe.outfit.set_ids(worn)
	await t.seconds(0.3)


## The gun held up toward the camera and away from it (the slot of a gun, when it carries one).
func _shoot_aiming(t: TestContext) -> void:
	var slot: int = _character.inventory.gun_slot()
	if slot > 0:
		_character.inventory.select_slot(slot)
	for look: String in ["", "_away"]:
		var toward := Vector2(1, 1) if look == "" else Vector2(-1, -1)
		_character.movement.aim_point = _character.global_position + toward * 200.0
		await t.seconds(0.8)
		await _shoot_zooms(t, "aiming%s" % look)


## The character walking east: the shots are taken on the move (the legs and arms swing).
func _shoot_walking(t: TestContext) -> void:
	_character.movement.aim_point = _character.global_position + Vector2(200.0, 0.0)
	for zoom: float in ZOOMS:
		_character.movement.move_input = Vector2.RIGHT
		await t.seconds(0.5)
		await _shoot(t, "walking_zoom%d" % int(zoom), zoom)
		_character.movement.move_input = Vector2.ZERO
	_character.movement.move_input = Vector2.ZERO


## The shot `name` at each zoom, `_zoom<n>` after it.
func _shoot_zooms(t: TestContext, name: String) -> void:
	for zoom: float in ZOOMS:
		await _shoot(t, "%s_zoom%d" % [name, int(zoom)], zoom)


## Park the live 2D camera over the character at `zoom` and save the picture as `<name>.png` in the
## folder `CHARMESH_SHOTS` names (nothing when it is unset). The camera is taken from the match
## each time: the match may replace it.
func _shoot(t: TestContext, name: String, zoom: float) -> void:
	var camera := _main.get_node_or_null("MainCamera") as Camera2D
	if camera == null:
		camera = _window.get_camera_2d()
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = _character.global_position
	await t.frames(8)
	# A window the desktop covers is not drawn: the viewport is drawn on demand then.
	RenderingServer.force_draw(false)
	var folder := OS.get_environment("CHARMESH_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		_window.get_texture().get_image().save_png("%s/%s.png" % [folder, name])


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
