extends GameTest
## The look gate's shots: one scene of the integrated game in a real window, in 3D at the zoom
## steps and the four camera turns, or in 2D at the zoom steps (windowed only: the headless
## renderer draws nothing; #193 phase 2b, General). One scene per run (a second window in one run
## has crashed Godot), picked by the environment:
##
## - `LOOK_SCENE` one of `street` (cars and street furniture), `bedroom`, `kitchen`, `office`
##   (a house's rooms), `firefight` (two characters trading shots: blood, debris, casings),
##   `grenade` (a frag burst, then a stun flash), `chars` (standing, crouched, fallen, aiming,
##   helmeted and dressed characters, guns held and lying), `car` (a car with a door open),
##   `glass` (a shattered glass door); `street` when unset. `turn` and `pan` measure instead of
##   shoot: the picture's flicker (a pixel that changes and changes back) while the camera turns
##   1.5 degrees a frame / pans, printed as `LOOKGATE` lines, at zoom 1 and 3, with the post's
##   supersample 1 and 2 (the turn's), and for `pan` at pitch 80 and 90.
## - `LOOK_DIR` the folder the pictures go to (`<scene>_<mode>_z<zoom>_yaw<yaw>.png`); none: nothing
##   saved.
## - `LOOK_MODE` `3d` (default) or `2d`.
## - `LOOK_ZOOMS` (default `0.5,1,2,3`) and `LOOK_YAWS` (`0,90,180,270`, 3D only; 2D has no turn).
##   A scene that moves (`firefight`, `grenade`) shoots one zoom and yaw per moment instead, the
##   pairs `LOOK_MOMENTS` names (`zoom:yaw,...`, default `1:0,2:0,3:0,2:90,1:180,1:270`).
## - `LOOK_FRAMES` the frames a shot waits after parking the camera (12; a flash's peak: 2).
## - `LOOK_AT` (`dx,dy`) shifts a room scene's camera from the room's middle, in px.
## - `LOOK_PLAN` the house plan (a room scene picks its own when unset), `LOOK_SEED`.
## Run:
## `LOOK_SCENE=street LOOK_DIR=<dir> tools/run_tests.sh --windowed
## --id=general/render_3d_look_gate_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const CharacterScene := preload("res://scenes/character/character_base.tscn")
const CarScene := preload("res://scenes/vehicle/car.tscn")
const VanScene := preload("res://scenes/vehicle/van.tscn")
const SCRATCH := "user://settings_render_3d_look_gate_windowed_test.json"
const SIZE := Vector2i(1152, 648)
## The house plan and the room type each room scene shoots (`LOOK_PLAN` overrides the plan).
const ROOM_SCENES := {
	"bedroom": { "plan": "two_bed_flat", "type": "bedroom" },
	"kitchen": { "plan": "starter_home", "type": "kitchen" },
	"office": { "plan": "office_loft", "type": "home_office" },
}
const MOVING := ["firefight", "grenade"]
const DEFAULT_MOMENTS := "1:0,2:0,3:0,2:90,1:180,1:270"
# --- flicker ------------------------------------------------------------------------------
const FLICKER_FRAMES := 62
const FLICKER_COLUMNS := 192
const FLICKER_ROWS := 108
## A change of colour that counts (the sum of the channels' difference, of 1 each).
const FLICKER_CHANGED := 0.06

var _window: SubViewport
var _main: Node
var _camera: Camera2D
var _rig: CameraRig
var _world: Node
var _house_node: Node2D
var _district: Node2D
var _scene := "street"
var _three_d := true
var _zooms: Array[float] = [0.5, 1.0, 2.0, 3.0]
var _yaws: Array[float] = [0.0, 90.0, 180.0, 270.0]
var _moments: Array[Vector2] = []


func describe() -> Dictionary:
	return {
		"name": "A look-gate scene of the integrated game, shot in a window (windowed)",
		"description": "One scene (street, a house's rooms, a firefight, a grenade burst, the "
			+ "characters, a car with a door open, a shattered glass door) at the zoom steps "
			+ "and the four camera turns, in 3D or 2D: drawn without shader or engine errors. "
			+ "Windowed only; the pictures are saved when LOOK_DIR names a folder.",
		"tags": ["render", "3d", "windowed", "look-gate"],
		"timeout": 600.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	var two_d := OS.get_environment("LOOK_MODE") == "2d"
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D if two_d else Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.switch(&"vision.enabled", false)  # the whole scene in view
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	_read_environment()
	if not await _start(t):
		return
	match _scene:
		"street":
			await _street(t, false)
		"car":
			await _street(t, true)
		"bedroom", "kitchen", "office":
			await _room(t)
		"firefight":
			await _firefight(t)
		"grenade":
			await _grenade(t)
		"chars":
			await _characters(t)
		"turn", "pan":
			await _flicker(t)
		"glass":
			await _glass(t)
		_:
			t.check(false, "LOOK_SCENE names a scene (got %s)" % _scene)
	await MainProbe.close(t, _window)


func _read_environment() -> void:
	_scene = OS.get_environment("LOOK_SCENE")
	if _scene == "":
		_scene = "street"
	_three_d = OS.get_environment("LOOK_MODE") != "2d"
	_zooms = _floats("LOOK_ZOOMS", _zooms)
	_yaws = _floats("LOOK_YAWS", _yaws)
	var spec := OS.get_environment("LOOK_MOMENTS")
	for pair: String in (spec if spec != "" else DEFAULT_MOMENTS).split(",", false):
		var parts := pair.split(":")
		_moments.append(Vector2(float(parts[0]), float(parts[1]) if parts.size() > 1 else 0.0))


## `LOOK_AT` (`dx,dy`, px): how far from its middle a room scene's camera parks (a doorway's
## close-up).
func _offset() -> Vector2:
	var parts := OS.get_environment("LOOK_AT").split(",", false)
	return Vector2(float(parts[0]), float(parts[1])) if parts.size() == 2 else Vector2.ZERO


func _floats(key: String, fallback: Array[float]) -> Array[float]:
	var text := OS.get_environment(key)
	if text == "":
		return fallback
	var out: Array[float] = []
	for part: String in text.split(",", false):
		out.append(float(part))
	return out


## Open the window and the match of the scene.
func _start(t: TestContext) -> bool:
	_window = SubViewport.new()
	_window.size = SIZE
	_window.world_2d = World2D.new()
	_window.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(_window)
	_main = MainProbe.open(_window)
	MainProbe.setup_menu(_main).queue_free()
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	_main.add_child(_camera)
	_camera.make_current()
	var spec := {
		"seed": maxi(int(OS.get_environment("LOOK_SEED")), 2),
		"defenders": { "count": 1 },
		"invaders": { "count": 1 },
	}
	var plan := OS.get_environment("LOOK_PLAN")
	if plan == "" and ROOM_SCENES.has(_scene):
		plan = ROOM_SCENES[_scene]["plan"]
	if plan == "" and _scene in ["firefight", "grenade", "chars", "glass", "turn", "pan"]:
		plan = "starter_home"
	if plan != "":
		spec["plan"] = plan
	var built: Dictionary = await _main.start_match(spec)
	if not t.require(not built.is_empty(), "a match started"):
		return false
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_world = built["world"]
	_house_node = built["house"]
	_district = built["district"]
	var view := _main.get_node_or_null("View3D")
	if _three_d:
		if not t.require(view != null, "Main built the 3D view"):
			return false
		_rig = view.rig
	_send_others_away(null)
	await t.frames(30)
	return true


# --- the scenes ---------------------------------------------------------------------------


## The street in front of the house, a car and a van parked on its road (a door of the car open for
## the `car` scene), the street's lamps and clutter on its pavement.
func _street(t: TestContext, doors_open: bool) -> void:
	var road := _nearest_road()
	var spot := _house_centre()
	if road.size != Vector2.ZERO:
		if road.size.x >= road.size.y:
			spot = Vector2(clampf(spot.x, road.position.x, road.end.x), road.get_center().y)
		else:
			spot = Vector2(road.get_center().x, clampf(spot.y, road.position.y, road.end.y))
	var along := Vector2.RIGHT if road.size.x >= road.size.y else Vector2.DOWN
	var car := CarScene.instantiate() as RigidBody2D
	var van := VanScene.instantiate() as RigidBody2D
	car.position = spot - along * 150.0
	van.position = spot + along * 170.0
	car.rotation = along.angle()
	van.rotation = along.angle()
	_world.add_child(car)
	_world.add_child(van)
	await t.frames(20)
	if doors_open:
		car.cabin.door(&"front_left").open()
		car.cabin.door(&"rear_right").open()
		for id: StringName in [&"side", &"rear_left"]:
			van.cabin.door(id).open()
		await t.seconds(0.8)
	var at := spot - along * 150.0 if doors_open else spot
	await _sweep(t, _scene, at)


## A room of the scene's type, the camera over it.
func _room(t: TestContext) -> void:
	var rooms: Array = WorldGen.get_rooms(_house())
	var wanted: String = ROOM_SCENES[_scene]["type"]
	var chosen: Dictionary = {}
	for room: Dictionary in rooms:
		if String(room["type"]) == wanted:
			chosen = room
			break
	if chosen.is_empty():
		t.check(
			false,
			"the plan has a %s (rooms: %s)" % [wanted, rooms.map(func(r): return r["type"])],
		)
		chosen = rooms[0]
	await _sweep(t, _scene, (chosen["rect"] as Rect2).get_center() + _offset())


## Two characters facing each other across a room, trading fire: blood, debris and casings.
func _firefight(t: TestContext) -> void:
	var room := _open_room()
	var centre := room.get_center()
	var left := _spawn(centre + Vector2(-110, 0), "tactical", false)
	var right := _spawn(centre + Vector2(110, 0), "helmeted", false)
	left.health = 400.0
	right.health = 400.0
	_aim(left, right.global_position)
	_aim(right, left.global_position)
	for c: CharacterBody2D in [left, right]:
		var slot: int = c.inventory.gun_slot()
		if slot > 0:
			c.inventory.select_slot(slot)
	await t.seconds(0.6)
	for moment: Vector2 in _moments:
		_set_yaw(moment.y)
		for burst in 8:
			for c: CharacterBody2D in [left, right]:
				if not c.is_dead:
					c.weapon.shoot()
			await t.seconds(0.12)
		await _shot(t, "firefight", centre, moment.x, moment.y)


## A frag burst (fire, smoke, flash), then a stun's flash, at five moments of the burst.
func _grenade(t: TestContext) -> void:
	var centre := _open_room().get_center()
	var row := GrenadeConfig.row(&"frag")
	var times := [0.1, 0.5, 1.2, 2.5]
	Explosion.frag(centre, _world, null, row)
	var passed := 0.0
	for i in _moments.size():
		var moment: Vector2 = _moments[i]
		_set_yaw(moment.y)
		var target: float = times[mini(i, times.size() - 1)] + 0.4 * maxi(0, i - times.size() + 1)
		await t.seconds(maxf(target - passed, 0.05))
		passed = target
		await _shot(t, "grenade", centre, moment.x, moment.y)
	var stun_at := centre + Vector2(60, 40)
	Explosion.stun(stun_at, _world, null, GrenadeConfig.row(&"stun"))
	await t.seconds(0.08)
	await _shot(t, "grenade_stun", stun_at, 2.0, 0.0)


## A line-up: standing in two outfits, crouched, fallen, aiming, helmeted and in a vest, a gun
## held out and a gun lying where it fell.
func _characters(t: TestContext) -> void:
	var room := _open_room()
	var centre := room.get_center()
	var kinds := [
		"casual", "helmeted", "tactical", "aiming",
		"crouched", "fallen", "dropped", "walking",
	]
	var people: Array[CharacterBody2D] = []
	for i in kinds.size():
		var col := i % 4
		var row := int(i / 4.0)
		var at := centre + Vector2((col - 1.5) * 70.0, (row - 0.5) * 80.0)
		people.append(_spawn(at, kinds[i], true))
	await t.seconds(0.8)
	people[4].movement.set_posture(&"crouch")
	people[5].health = 1.0
	people[5].take_damage(1000.0)
	people[6].inventory.drop_held(Vector2(40.0, 0.0))
	people[7].movement.move_input = Vector2.RIGHT
	await t.seconds(1.4)
	await _sweep(t, "chars", centre)


## A glass door shattered, then knocked down.
func _glass(t: TestContext) -> void:
	var door: Node2D = null
	for entry: Dictionary in WorldGen.get_doors(_house()):
		if entry["opening"]["front"]:
			door = entry["node"]
	if door == null:
		for node: Node in _world.get_tree().get_nodes_in_group(&"doors"):
			if _world.is_ancestor_of(node):
				door = node as Node2D
				break
	if not t.require(door != null, "the match has a house door"):
		return
	door.look.material = "glass"
	door.look.style = "panes"
	door.look.broken = true
	door.visuals.refresh()
	await t.frames(10)
	await _sweep(t, "glass", door.global_position)
	door.take_damage(10_000.0)
	await t.frames(10)
	await _sweep(t, "glass_down", door.global_position)


## The camera turning (`turn`) or panning (`pan`) over a room: how many picture pixels of its
## middle changed and changed back the next frame, per zoom and supersample.
func _flicker(t: TestContext) -> void:
	var at := _open_room().get_center()
	var pitches := [RenderConfig.pitch_degrees]
	if _scene == "pan":
		pitches = [RenderConfig.pitch_degrees, 90.0]
	var was_pitch := RenderConfig.pitch_degrees
	for pitch: float in pitches:
		RenderConfig.pitch_degrees = pitch
		for zoom: int in [1, 3]:
			for supersample: int in [1, 2]:
				_rig.oversample = supersample
				_rig.turn_oversample = supersample
				var row := await _flicker_run(t, at, zoom)
				print("LOOKGATE %s pitch=%d zoom=%d supersample=%d flicker=%d changed=%d" % [
					_scene, pitch, zoom, supersample, row["flicker"], row["changed"],
				])
	RenderConfig.pitch_degrees = was_pitch


## One run of `FLICKER_FRAMES` frames over `at`; `{ flicker, changed }`.
func _flicker_run(t: TestContext, at: Vector2, zoom: int) -> Dictionary:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.global_position = at
	_set_yaw(0.0)
	await t.frames(8)
	var frames: Array[PackedInt32Array] = []
	for n in FLICKER_FRAMES:
		if _scene == "turn":
			_set_yaw(1.5 * n)
		else:
			_camera.global_position = at + Vector2(0.0, 0.5 * n)
		await t.frames(1)
		RenderingServer.force_draw(false)
		var image := _window.get_texture().get_image()
		frames.append(_sample(image, zoom))
		var dir := OS.get_environment("LOOK_DIR")
		if dir != "" and n in [20, 21]:
			DirAccess.make_dir_recursive_absolute(dir)
			image.save_png("%s/%s_z%d_ss%d_frame%d.png" % [dir, _scene, zoom, _rig.oversample, n])
	var flicker := 0
	var changed := 0
	for n in range(1, frames.size() - 1):
		for i in frames[n].size():
			if _differs(frames[n - 1][i], frames[n][i]):
				changed += 1
				if not _differs(frames[n - 1][i], frames[n + 1][i]):
					flicker += 1
	return { "flicker": flicker, "changed": changed }


## One colour per picture pixel of the middle of the picture (the middle of each `zoom`-pixel
## block).
func _sample(image: Image, zoom: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var from := Vector2i(
		(SIZE.x - FLICKER_COLUMNS * zoom) >> 1,
		(SIZE.y - FLICKER_ROWS * zoom) >> 1,
	)
	for row in FLICKER_ROWS:
		for column in FLICKER_COLUMNS:
			var spot := from + Vector2i(column, row) * zoom + Vector2i(zoom >> 1, zoom >> 1)
			out.append(image.get_pixel(spot.x, spot.y).to_rgba32() >> 8)
	return out


func _differs(a: int, b: int) -> bool:
	var sum := absi(((a >> 16) & 255) - ((b >> 16) & 255))
	sum += absi(((a >> 8) & 255) - ((b >> 8) & 255)) + absi((a & 255) - (b & 255))
	return float(sum) / 255.0 > FLICKER_CHANGED


# --- shots --------------------------------------------------------------------------------


## The scene at every zoom and turn: 2D has no turn, so one shot per zoom.
func _sweep(t: TestContext, name: String, at: Vector2) -> void:
	var yaws: Array[float] = _yaws
	if not _three_d:
		yaws = [0.0]
	for zoom: float in _zooms:
		for yaw: float in yaws:
			_set_yaw(yaw)
			await _shot(t, name, at, zoom, yaw)


## Park the camera over `at` at `zoom`, draw and save `<name>_<mode>_z<zoom>_yaw<yaw>.png`.
func _shot(t: TestContext, name: String, at: Vector2, zoom: float, yaw: float) -> void:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.global_position = at
	var settle := int(OS.get_environment("LOOK_FRAMES"))
	await t.frames(settle if settle > 0 else 12)
	# A window the desktop covers is not drawn and never signals frame_post_draw: draw the viewport
	# on demand (synchronously) and read it back at once.
	RenderingServer.force_draw(false)
	_print_lights(t, name, zoom)
	var dir := OS.get_environment("LOOK_DIR")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var zoom_text := ("%.1f" % zoom).replace(".0", "").replace(".", "p")
	var shot := "%s/%s_%s_z%s_yaw%d.png" % [dir, name, "3d" if _three_d else "2d", zoom_text, yaw]
	_window.get_texture().get_image().save_png(shot)


## Print the 3D lights' counts at this shot (`LOOKLIGHTS`: how many exist, reach the view, are on
## and cast a shadow), and with `LOOK_LIGHTS` set each light that is on (`LOOKLIGHT`).
func _print_lights(t: TestContext, name: String, zoom: float) -> void:
	var lighting := t.world.get_tree().get_first_node_in_group(&"world_lighting_3d")
	if not lighting is WorldLighting3D:
		return
	var world_lights := lighting as WorldLighting3D
	print("LOOKLIGHTS %s zoom=%s lights=%d in_view=%d on=%d shadowed=%d" % [
		name, zoom, world_lights.lights().size(), world_lights.in_view_count(),
		world_lights.on_count(), world_lights.shadowed_count(),
	])
	if OS.get_environment("LOOK_LIGHTS") == "":
		return
	for l: OmniLight3D in world_lights.lights():
		if l.visible:
			print("LOOKLIGHT %s at=(%d,%d) energy=%.2f room=%d reach=%d" % [
				l.name, l.position.x, l.position.z, l.light_energy, int(l.get_meta(&"room")),
				sqrt(maxf(l.omni_range * l.omni_range - l.position.y * l.position.y, 0.0)),
			])


func _set_yaw(yaw: float) -> void:
	if _rig != null:
		_rig.yaw = yaw


# --- the world ----------------------------------------------------------------------------


## The match's house (the centre tower).
func _house() -> Node2D:
	return _house_node


## The road of the district nearest the house, as a world rect; empty with none.
func _nearest_road() -> Rect2:
	var best := Rect2()
	var best_gap := INF
	var at := _house_centre()
	for piece: Dictionary in DistrictReads.get_district_street(_district):
		if piece["role"] != &"road" and piece["role"] != "road":
			continue
		var rect: Rect2 = piece["rect"]
		var near := Vector2(
			clampf(at.x, rect.position.x, rect.end.x), clampf(at.y, rect.position.y, rect.end.y)
		)
		if near.distance_to(at) < best_gap:
			best_gap = near.distance_to(at)
			best = rect
	return best


## The middle of the match's house floors (the street is not part of it).
func _house_centre() -> Vector2:
	var bounds := Rect2()
	var first := true
	for node: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			bounds = rect if first else bounds.merge(rect)
			first = false
	return bounds.get_center()


## The house's largest room, its pieces and the match's two characters sent off the shot.
func _open_room() -> Rect2:
	var best := Rect2()
	for room: Dictionary in WorldGen.get_rooms(_house()):
		var rect: Rect2 = room["rect"]
		if rect.get_area() > best.get_area():
			best = rect
	_hide_pieces_in(best)
	return best


## Hide the furniture in `rect` (and its clutter) so a line-up or a duel stands clear: the body
## itself, so 2D stops drawing it and the 3D mirror hides its mesh with it.
func _hide_pieces_in(rect: Rect2) -> void:
	for body: Node in _world.find_children("*", "PhysicsBody2D", true, false):
		var node := body as Node2D
		if (rect.grow(20.0).has_point(node.global_position)
				and MirrorProxy.kind_of(body) == MirrorProxy.FURNITURE):
			node.visible = false


## One character at `at`, dressed and posed by `kind`; nobody shoots it when `safe`.
func _spawn(at: Vector2, kind: String, safe: bool) -> CharacterBody2D:
	var c := CharacterScene.instantiate() as CharacterBody2D
	c.global_position = at
	_world.add_child(c)
	c.movement.controller = null
	c.movement.move_input = Vector2.ZERO
	if safe:
		c.health = 1.0e9
	var worn := {
		"casual": { "head": &"hat", "body": &"tshirt", "pants": &"jeans", "feet": &"shoes" },
		"helmeted": {
			"head": &"helmet", "vest": &"plate_carrier", "front_plate": &"ceramic_iv",
			"body": &"shirt", "pants": &"tactical_pants", "feet": &"boots",
		},
		"tactical": {
			"vest": &"tactical_vest", "body": &"shirt", "pants": &"tactical_pants",
			"feet": &"boots",
		},
	}
	var outfit: Dictionary = worn.get(kind, worn["casual"])
	c.wardrobe.outfit.set_ids(outfit)
	_aim(c, at + Vector2(200.0, 200.0))
	if kind in ["aiming", "walking", "dropped", "tactical", "helmeted"]:
		var slot: int = c.inventory.gun_slot()
		if slot > 0:
			c.inventory.select_slot(slot)
	return c


func _aim(c: CharacterBody2D, point: Vector2) -> void:
	c.movement.aim_point = point


## The match's own characters moved far off, except `keep`.
func _send_others_away(keep: Node2D) -> void:
	for body: Node in _world.find_children("*", "CharacterBody2D", true, false):
		if body != keep:
			(body as Node2D).global_position = Vector2(-6000.0, -6000.0)
