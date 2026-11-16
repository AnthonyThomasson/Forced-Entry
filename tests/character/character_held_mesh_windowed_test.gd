extends GameTest
## The held item and the fallen body of a 3D match in a real window (windowed only: the headless
## renderer draws nothing and compiles no shader; #193 phase 2, Character and Items). A Watch match
## started with 3D chosen, the camera over one of its characters, zoomed in and at the game's
## default: the character holds each item in turn, the picture is drawn, and the log gate fails the
## test on any shader or engine error. The look itself is not asserted: with `HELD_SHOTS=<dir>` set
## it saves a picture of a rifle and of a pistol held toward the camera and across it, a grenade
## wound up for the throw, a rifle raised off a wall and the body dead, at zoom 3 and zoom 1, for
## the phase gate (`HELD_PITCH=<degrees>` tips the camera). Run:
## `tools/run_tests.sh --windowed --id=character/character_held_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_character_held_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## The two zooms of the shots: close, and the game's default (`CameraRig` follows the 2D camera's).
const ZOOMS := [3.0, 1.0]
## Where the aim points from the character, toward the camera (the shots' south edge) and across it.
const TOWARD := Vector2(1, 1)
const ACROSS := Vector2(1, -1)


func describe() -> Dictionary:
	return {
		"name": "A 3D match shows held items and a fallen body without shader errors (windowed)",
		"description": "A 3D Watch match, the camera over one character holding a rifle, a pistol "
			+ "and a grenade in turn and then dead: the picture is drawn. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "character", "items"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	if OS.get_environment("HELD_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("HELD_PITCH")))
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	# A long wind-up, so the picture of the throw is taken with the arm drawn back.
	var rows := GrenadeConfig.grenades.duplicate(true)
	rows[&"frag"]["windup"] = 30.0
	s.set_static(GrenadeConfig, &"grenades", rows)
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
	var view: Node = main.get_node("View3D")
	var mirror: WorldMirror = view.mirror
	_hide_walls(built["world"], mirror)  # full-height walls would stand between the camera and it
	var shown := mirror.proxies_of(character)
	if not t.require(shown.size() == 1 and shown[0] is BodyMesh, "the character has a body"):
		return
	character.movement.controller = null
	character.movement.move_input = Vector2.ZERO
	Probe.arm(character, 0, 2, &"rifle")
	await _hold(t, window, camera, character, 6)
	Probe.arm(character, 0, 2, &"pistol")
	await _hold(t, window, camera, character, 3)
	await _throw(t, window, camera, character)
	await _die(t, window, camera, character)
	await MainProbe.close(t, window)


## The character holding the item in `slot`, aimed toward the camera and across it, at each zoom.
func _hold(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
	slot: int,
) -> void:
	var name := "rifle" if slot == 6 else "pistol"
	character.inventory.select_slot(slot)
	for look: Array in [["", TOWARD], ["_across", ACROSS]]:
		character.movement.aim_point = character.global_position + (look[1] as Vector2) * 200.0
		await t.seconds(0.6)
		for zoom: float in ZOOMS:
			camera.zoom = Vector2(zoom, zoom)
			await _shoot(t, window, camera, character, "%s%s_zoom%d" % [name, look[0], int(zoom)])


## A frag grenade wound up for the throw: the arm drawn back, the grenade in the hand.
func _throw(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
) -> void:
	character.inventory.select_slot(8)
	character.movement.aim_point = character.global_position + ACROSS * 200.0
	await t.seconds(0.4)
	character.weapon.shoot()
	await t.seconds(0.5)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		await _shoot(t, window, camera, character, "throw_zoom%d" % int(zoom))


## The body dead: where the ragdoll laid it, settled.
func _die(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
) -> void:
	character.inventory.select_slot(6)
	await t.seconds(0.3)
	character.take_damage(1000.0)
	await t.until(func(): return character.anatomy.ragdoll.is_settled(), 8.0)
	await t.seconds(0.5)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		await _shoot(t, window, camera, character, "dead_zoom%d" % int(zoom))


## Park the camera over `character` and save the picture as `<name>.png` in the folder
## `HELD_SHOTS` names (nothing when it is unset).
func _shoot(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
	name: String,
) -> void:
	camera.global_position = character.global_position
	await t.frames(8)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var folder := OS.get_environment("HELD_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		window.get_texture().get_image().save_png("%s/%s.png" % [folder, name])


## Hide the proxies of every wall, so the picture shows what stands inside the rooms.
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
