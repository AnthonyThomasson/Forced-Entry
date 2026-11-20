extends GameTest
## The effects of Physics in a 3D match, in a real window (windowed only: the headless renderer
## draws nothing and compiles no shader; #193 phase 2, Physics). A Watch match started with 3D
## chosen, the camera over one of its characters: a firefight (chips and sparks flung off wood and
## metal, a character shot dead and bleeding out into splats and a pool) and a frag going off beside
## it (mid-blast, in the smoke, and its scorch after). The picture is drawn, and the log gate fails
## the test on any shader or engine error. The look itself is not asserted: with
## `PHYSICS_SHOTS=<dir>` set it saves a picture of each at zoom 3 and at the game's default zoom 1,
## for the phase gate. Run: `tools/run_tests.sh --windowed --id=physics/physics_mesh_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const SCRATCH := "user://settings_physics_mesh_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## The two zooms of the shots: close, and the game's default (`CameraRig` follows the 2D camera's).
const ZOOMS := [3.0, 1.0]
## Hits of the firefight, one a frame.
const HITS := 36

## The window the match draws in, its camera, the world and the effects' layer.
var _window: SubViewport
var _camera: Camera2D
var _world: Node
var _layer: FxLayer


func describe() -> Dictionary:
	return {
		"name": "A 3D match shows chips, sparks, blood and a blast (windowed)",
		"description": "A 3D Watch match with a firefight, a character bleeding out and a frag "
			+ "going off: the picture is drawn without shader errors. Windowed only.",
		"tags": ["render", "3d", "windowed", "physics", "blood", "explosion"],
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
	if not t.require(not built.is_empty(), "a Watch match started in 3D"):
		return
	var victim := _first_character(built["world"])
	if not t.require(victim != null, "the match has a living character"):
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	var view: Node = main.get_node("View3D")
	var mirror: MeshCarrier = view.carrier
	_hide_walls(built["world"], mirror)
	victim.movement.controller = null
	victim.movement.move_input = Vector2.ZERO
	_layer = view.viewport.get_node("FxLayer")
	_world = built["world"]
	var focus := victim.global_position
	await _firefight(t, focus)
	await _road_firefight(t)
	await _bleed(t, victim)
	await _blast(t, focus + Vector2(70, 0))
	await MainProbe.close(t, _window)


## Hits flung at wood and metal around the focus, one a frame, the picture taken in the middle.
func _firefight(t: TestContext, focus: Vector2) -> void:
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_camera.global_position = focus
		for i in HITS:
			_hit(_world, focus + Vector2(randf_range(-50, 50), randf_range(-30, 30)), i)
			await t.frames(1)
			if i == int(HITS * 0.5):
				t.check(_layer.bursts.shown() > 0, "bits fly at zoom %d" % int(zoom))
				await _save(t, "firefight_zoom%d" % int(zoom))
		await t.seconds(1.5)
		t.check(_layer.debris.lying() > 0, "chips lie after it at zoom %d" % int(zoom))
		await _save(t, "firefight_after_zoom%d" % int(zoom))


## The same firefight on a road (a kerb lower than the pavement), its blood and chips lying on it.
func _road_firefight(t: TestContext) -> void:
	var road := _road(_world)
	if not t.require(road.size != Vector2.ZERO, "the match has a road"):
		return
	var focus := road.get_center()
	var ground := StreetGround.new()
	ground.refresh(_world)
	t.check(ground.offset_at(focus) < 0.0, "the ground is a kerb lower at its middle")
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_camera.global_position = focus
		for i in HITS:
			_hit(_world, focus + Vector2(randf_range(-50, 50), randf_range(-30, 30)), i)
			if i % 6 == 0:
				_splat(_world, focus + Vector2(randf_range(-40, 40), randf_range(-25, 25)))
			await t.frames(1)
			if i == int(HITS * 0.5):
				await _save(t, "road_firefight_zoom%d" % int(zoom))
		await t.seconds(1.5)
		await _save(t, "road_firefight_after_zoom%d" % int(zoom))
		Physics.spawn_explosion(_world, focus, &"frag")
		await t.seconds(0.15)
		await _save(t, "road_blast_zoom%d" % int(zoom))
		await t.seconds(4.5)


## One splat of blood at `at`.
func _splat(world: Node, at: Vector2) -> void:
	var throw := BloodThrow.new()
	throw.size = 3.5
	throw.energy = 0.6
	BloodSpawner.splat(world, at, throw)


## The first road floor of the match (a street floor that is not the sidewalk), or an empty rect.
func _road(world: Node) -> Rect2:
	for node: Node in get_tree_floors(world):
		var opts: Variant = node.get("art_opts")
		var kind := String(opts.get("kind", "asphalt")) if opts is Dictionary else "asphalt"
		if MeshKinds.art_of(node) == "street" and kind != "sidewalk":
			return Rect2((node as Node2D).global_position, node.get("size"))
	return Rect2()


## The floors in `world`.
func get_tree_floors(world: Node) -> Array[Node]:
	return world.get_tree().get_nodes_in_group(&"floors").filter(
		func(n: Node) -> bool: return world.is_ancestor_of(n)
	)


## The character dead: splats at once, its pool filling.
func _bleed(t: TestContext, victim: Node2D) -> void:
	victim.take_damage(1000.0)
	await t.until(func(): return victim.anatomy.ragdoll.is_settled(), 8.0)
	t.check(
		await t.until(func(): return _layer.pools.builds > 0, 15.0, "a pool begins"),
		"the character bleeds out into a pool",
	)
	await t.seconds(6.0)
	t.check(_layer.ink.count_of(InkMark.Kind.SPLAT) > 0, "its blood splatters the floor")
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_camera.global_position = victim.global_position
		await _save(t, "blood_zoom%d" % int(zoom))


## A frag: its blast in the middle, in the smoke, and the scorch when it is over.
func _blast(t: TestContext, at: Vector2) -> void:
	for zoom: float in ZOOMS:
		_camera.zoom = Vector2(zoom, zoom)
		_camera.global_position = at
		await t.seconds(0.3)
		Physics.spawn_explosion(_world, at, &"frag")
		t.check(_layer.blasts.shown() > 0, "the blast is on at zoom %d" % int(zoom))
		await _save(t, "blast_flash_zoom%d" % int(zoom))
		await t.seconds(0.12)
		await _save(t, "blast_fire_zoom%d" % int(zoom))
		await t.seconds(1.2)
		await _save(t, "blast_smoke_zoom%d" % int(zoom))
		await t.seconds(4.0)
		await _save(t, "blast_scorch_zoom%d" % int(zoom))


## A hit at `at`: `i` odd on metal (sparks), even on wood (chips), at a height from the floor to
## the top.
func _hit(world: Node, at: Vector2, i: int) -> void:
	var hit := HitInfo.new()
	hit.position = at
	hit.normal = Vector2.from_angle(randf() * TAU)
	hit.direction = -hit.normal
	hit.height = float(i % 4) * 30.0
	var wood := i % 2 == 0
	var surface := {
		"material": "wood" if wood else "metal",
		"color": Color(0.55, 0.38, 0.2) if wood else Color(0.5, 0.52, 0.56),
	}
	Physics.spawn_debris(world, hit, surface)


## Save the picture as `<name>.png` in the folder `PHYSICS_SHOTS` names (nothing when it is unset).
func _save(t: TestContext, name: String) -> void:
	await t.frames(2)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var folder := OS.get_environment("PHYSICS_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		_window.get_texture().get_image().save_png("%s/%s.png" % [folder, name])


## Hide the proxies of every wall, so the picture shows what stands inside the rooms.
func _hide_walls(world: Node, mirror: MeshCarrier) -> void:
	for body: Node in PlanProbe.bodies_under(world):
		if MeshKinds.kind_of(body) in [MeshKinds.WALL, MeshKinds.DOOR]:
			for proxy in mirror.proxies_of(body):
				proxy.visible = false


## The first living character the match built.
func _first_character(world: Node) -> CharacterBody2D:
	for body: Node in world.find_children("*", "CharacterBody2D", true, false):
		if not body.get("is_dead"):
			return body as CharacterBody2D
	return null
