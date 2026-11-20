extends GameTest
## The loose items and the shots of a 3D match in a real window (windowed only: the headless
## renderer draws nothing and compiles no shader; #193 phase 2, Items and Projectile). A Watch match
## started with 3D chosen, the camera over one of its characters: a burst of rifle fire (tracers in
## the air, casings on the floor), a frag grenade thrown slowly (in the air, then lying) and the
## character dead beside the rifle it let go of; the picture is drawn, and the log gate fails the
## test on any shader or engine error. The look itself is not asserted: with `ITEMS_SHOTS=<dir>` set
## it saves a picture of each at zoom 3 and at the game's default zoom 1, for the phase gate
## (`ITEMS_PITCH=<degrees>` tips the camera). Run:
## `tools/run_tests.sh --windowed --id=items/items_projectile_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_items_projectile_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## The two zooms of the shots: close, and the game's default (`CameraRig` follows the 2D camera's).
const ZOOMS := [3.0, 1.0]
## How far (px) a clear line is looked for, and how many headings are tried.
const CLEAR_REACH := 400.0
const HEADINGS := 16
## Shots of the burst, fired one a frame while the picture is taken.
const BURST := 40

## The heading the shots fly along: the one from the character with the longest clear line at muzzle
## height (a level round meets a wall at once: a tracer needs room to fly through the picture).
var _across := Vector2(1, -1)


func describe() -> Dictionary:
	return {
		"name": "A 3D match shows tracers, casings, a grenade and a dropped rifle (windowed)",
		"description": "A 3D Watch match, a character firing a burst, throwing a frag and dying "
			+ "beside its rifle: the picture is drawn without shader errors. Windowed only.",
		"tags": ["render", "3d", "windowed", "meshkit", "items", "projectile"],
		"timeout": 180.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	if OS.get_environment("ITEMS_PITCH") != "":
		s.set_static(RenderConfig, &"pitch_degrees", float(OS.get_environment("ITEMS_PITCH")))
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	# A slow, long-fused throw, so the grenade is in the air and lying for a picture each.
	var rows := GrenadeConfig.grenades.duplicate(true)
	rows[&"frag"]["throw_speed"] = 160.0
	rows[&"frag"]["fuse"] = 120.0
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
	_across = _clearest_heading(character)
	var view: Node = main.get_node("View3D")
	var mirror: WorldMirror = view.mirror
	_hide_walls(built["world"], mirror)
	character.movement.controller = null
	character.movement.move_input = Vector2.ZERO
	Probe.arm(character, 0, 2, &"rifle")
	var layer: ShotLayer = view.viewport.get_node("ShotLayer")
	await _burst(t, window, camera, character, layer)
	await _throw(t, window, camera, character)
	await _die(t, window, camera, character, view.follower)
	await MainProbe.close(t, window)


## A burst of rifle fire across the screen: a shot a frame, the picture taken in the middle of it.
func _burst(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
	layer: ShotLayer,
) -> void:
	character.inventory.select_slot(6)
	character.movement.aim_point = character.global_position + _across * 300.0
	await t.seconds(0.6)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		# The camera looks a little ahead of the muzzle, where the tracers fly through the picture.
		var ahead := _across.normalized() * (110.0 if zoom > 1.0 else 0.0)
		camera.global_position = character.global_position + ahead
		var seen := false
		for i in BURST:
			character.weapon.shoot()
			await t.frames(1)
			seen = seen or _tracer_in_view(layer, camera, zoom)
			if seen and i > 12:
				break
		t.check(layer.tracer_count() > 0, "tracers fly during the burst at zoom %d" % int(zoom))
		t.check(layer.casing_count() > 0, "casings lie after it at zoom %d" % int(zoom))
		await _save(t, window, "burst_zoom%d" % int(zoom))
		await t.seconds(1.0)


## Whether a tracer is within the picture around the camera's focus (a 2D px box that takes in
## what the zoom shows).
func _tracer_in_view(layer: ShotLayer, camera: Camera2D, zoom: float) -> bool:
	var half := Vector2(SIZE) * 0.45 / zoom
	var focus := camera.global_position
	for slot in layer.tracer_count():
		var at := layer.tracer_frame(slot).origin
		if absf(at.x - focus.x) < half.x and absf(at.z - focus.y) < half.y:
			return true
	return false


## A frag thrown slowly: in the air above the floor, then lying on it.
func _throw(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
) -> void:
	character.inventory.select_slot(8)
	character.movement.aim_point = character.global_position + _across * 240.0
	await t.seconds(0.4)
	character.weapon.shoot()
	if not t.require(
		await t.until(func(): return not Probe.live(t).is_empty(), 2.0), "the grenade is thrown"
	):
		return
	# a slow lob from the release height lands in half a second: look at it early in its flight
	await t.seconds(0.15)
	var grenade: Node2D = Probe.live(t)[0]
	t.check(grenade.altitude() > 20.0, "the grenade is in the air (%.0f px)" % grenade.altitude())
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = grenade.global_position
		await _save(t, window, "grenade_air_zoom%d" % int(zoom))
	await Probe.wait_rest(t, 15.0)
	await t.seconds(0.5)
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = grenade.global_position
		await _save(t, window, "grenade_lying_zoom%d" % int(zoom))


## The character dead, its rifle let go beside it.
func _die(
	t: TestContext,
	window: SubViewport,
	camera: Camera2D,
	character: Node2D,
	follower: MeshFollower,
) -> void:
	character.inventory.select_slot(6)
	await t.seconds(0.3)
	character.take_damage(1000.0)
	await t.until(func(): return character.anatomy.ragdoll.is_settled(), 8.0)
	await t.seconds(1.5)
	var rifles := t.world.get_tree().get_nodes_in_group(&"dropped_items")
	t.check(not rifles.is_empty(), "the dead character let go of its rifle")
	for item: Node2D in rifles:
		t.check(follower.mesh_of(item) != null, "the dropped rifle is shown")
	for zoom: float in ZOOMS:
		camera.zoom = Vector2(zoom, zoom)
		camera.global_position = character.global_position
		await _save(t, window, "dropped_rifle_zoom%d" % int(zoom))


## Save the picture as `<name>.png` in the folder `ITEMS_SHOTS` names (nothing when it is unset).
func _save(t: TestContext, window: SubViewport, name: String) -> void:
	await t.frames(2)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var folder := OS.get_environment("ITEMS_SHOTS")
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


## The heading (a unit vector; of equal reaches the first tried wins) from `character`
## along which a level line at its muzzle height runs farthest before it meets a twin.
func _clearest_heading(character: Node2D) -> Vector2:
	var space := TwinSpace.space_of(character)
	var from := PlanSpace.lift(character.global_position, BodyHeights.muzzle(BodyHeights.STAND))
	var best := Vector2(1, -1).normalized()
	var best_reach := -1.0
	for i in HEADINGS:
		var heading := Vector2.RIGHT.rotated(TAU * (float(i) + 0.5) / HEADINGS - PI * 0.25)
		var query := PhysicsRayQueryParameters3D.create(
			from,
			from + PlanSpace.lift(heading * CLEAR_REACH),
		)
		query.collision_mask = PhysicsLayers.TWIN_ALL
		var hit := space.intersect_ray(query)
		var reach := CLEAR_REACH if hit.is_empty() else from.distance_to(hit["position"])
		if reach > best_reach + 1.0:
			best_reach = reach
			best = heading
	return best
