extends GameTest
## #193 phase 3 (L3, L6 in 3D, windowed only: the headless renderer draws nothing and compiles no
## shader): a character's shadow is short and under it, whatever light stands near it, as the 2D
## drop shadow is. A Watch match in a real window, one character standing at each of four spots,
## the camera over it at zoom 2: under a room's ceiling fixture, far from it in the same room, in
## the street in the sun, and beside a street lamp (and beside a piece's lamp when the house has
## one). The picture is drawn with the character and again with it hidden: every pixel that differs
## is the character and its shadow, and none lies further from it than `REACH` px (a body, its arms
## and a gun reach 35, its drop shadow a few more; a light's shadow of a 74 tall body 100 or 200 px
## from a light 60 up, as the 3D render's first lights hung them, reaches past 100).
## Run: `tools/run_tests.sh --windowed --id=lighting/character_shadow_windowed`; with
## `CHARSHADOW_DIR=<dir>` set it saves each spot's picture (`<spot>_z2.png`, with the character
## and `<spot>_z1.png`, at the game's default zoom).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const CharacterScene := preload("res://scenes/character/character_base.tscn")
const SCRATCH := "user://settings_character_shadow_windowed_test.json"
const SIZE := Vector2i(1152, 648)
## How far (world px) from the character a pixel that differs may be.
const REACH := 64.0
## How much a pixel's channels must change (of 1 each, summed) to count as different.
const CHANGED := 0.12
## How far (px) from a fixture the "far" spot stands.
const FAR := 170.0
## How much darker (a share) the pixels round the body are with its drop shadow than without.
const PATCH_DARKER := 0.004

var _window: SubViewport
var _main: Node
var _camera: Camera2D
var _world: Node
var _lighting: WorldLighting3D
var _view: Node


## The picture of the window with the camera over `at` at `zoom`.
func _draw(t: TestContext, at: Vector2, zoom: float, settle := 40) -> Image:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.global_position = at
	await t.frames(settle)
	RenderingServer.force_draw(false)  # a covered window is not drawn: draw on demand
	return _window.get_texture().get_image()


func describe() -> Dictionary:
	return {
		"name": "A character's shadow is short and under it, near any light (windowed)",
		"description": "A character stands under a ceiling fixture, far from it, in the sun and "
			+ "beside a street lamp: what it changes in the picture lies within a few body "
			+ "radii of it. Windowed only.",
		"tags": ["lighting", "3d", "render", "windowed", "character"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.own_picture()
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.switch(&"vision.enabled", false)  # the whole scene in view
	s.set_static(WallFadeConfig, &"radius", 0.0)  # no wall thins: only the shadow differs
	s.lock_interaction([&"camera"])
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	if not await _start(t):
		return
	var person := _person()
	for spot: Dictionary in _spots(t):
		person.global_position = spot["at"]
		person.movement.aim_point = (spot["at"] as Vector2) + Vector2(200.0, 200.0)
		await _check_spot(t, person, spot)
	await MainProbe.close(t, _window)


## The window and the match (the house of the look gate's rooms).
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
	var spec := { "seed": 2, "plan": "starter_home", "defenders": { "count": 1 },
		"invaders": { "count": 1 } }
	var built: Dictionary = await _main.start_match(spec)
	if not t.require(not built.is_empty(), "a match started"):
		return false
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_world = built["world"]
	_view = _main.get_node_or_null("View3D")
	for body: Node in preload("res://tests/_general/plan_probe.gd").characters_under(_world):
		(body as Node2D).global_position = Vector2(-6000.0, -6000.0)
	_lighting = t.world.get_tree().get_first_node_in_group(&"world_lighting_3d") as WorldLighting3D
	t.require(_lighting != null, "the match is lit in 3D")
	await t.frames(30)
	return true


## One character, a bystander in the house.
func _person() -> Node2D:
	var c := CharacterScene.instantiate() as Node2D
	_world.add_child(c)
	c.movement.controller = null
	c.movement.move_input = Vector2.ZERO
	c.health = 1.0e9
	return c


## The spots, `{ name, at }`: where a fixture, a lamp and a street lamp are and the street.
func _spots(t: TestContext) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	for f: Dictionary in _lighting.fixtures():
		var light: OmniLight3D = f["light"]
		var at := Vector2(light.position.x, light.position.z) / RenderConfig.unit
		spots.append({ "name": "fixture", "at": at })
		spots.append({ "name": "far", "at": at + Vector2(-FAR * 0.8, FAR * 0.4) })
		break
	var street := _street_spot()
	if street != Vector2.ZERO:
		spots.append({ "name": "sun", "at": street })
	for l: OmniLight3D in _lighting.lights():
		if not l.has_meta(&"piece") or not is_instance_valid(l.get_meta(&"piece")):
			continue
		var piece: Node2D = l.get_meta(&"piece")
		var street_lamp: bool = ToonLight.sky_reaches(piece.global_position)
		var name := "street_lamp" if street_lamp else "lamp"
		if not spots.any(func(s: Dictionary) -> bool: return s["name"] == name):
			var at := Vector2(l.position.x, l.position.z) / RenderConfig.unit
			spots.append({ "name": name, "at": at + Vector2(24.0, 24.0) })
	t.check(spots.size() >= 3, "the match has spots to stand at (%d)" % spots.size())
	return spots


## A point of the street away from any light, where the sun is the only one.
func _street_spot() -> Vector2:
	var best := Vector2.ZERO
	var most := -1.0
	for ground: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if not ground.has_method(&"is_street") or not ground.call(&"is_street"):
			continue
		var rect := Rect2((ground as Node2D).global_position, ground.get("size"))
		var at := rect.get_center()
		var gap := INF
		for l: OmniLight3D in _lighting.lights():
			gap = minf(gap, Vector2(l.position.x, l.position.z).distance_to(at))
		if gap > most:
			most = gap
			best = at
	return best


## The picture with `person` at `spot` and again with it hidden: what differs lies within `REACH`.
func _check_spot(t: TestContext, person: Node2D, spot: Dictionary) -> void:
	var at: Vector2 = spot["at"]
	person.visible = true
	var with := await _draw(t, at, 2.0)
	var shot := _save(with, "%s_z2" % spot["name"])
	var with_z1 := await _draw(t, at, 1.0)
	_save(with_z1, "%s_z1" % spot["name"])
	await _check_patch_shows(t, person, spot, with)
	person.visible = false
	var pictures: Array[Image] = [await _draw(t, at, 2.0)]
	for visible_now: bool in [true, false, true]:
		person.visible = visible_now
		pictures.append(await _draw(t, at, 2.0, 5))
	var seen := _changed(pictures)
	var changed := int(seen.x)
	var far := seen.y
	t.check(changed > 20, "%s: the character is in the picture (%d pixels differ)" % [
		spot["name"], changed])
	t.check(
		far <= REACH,
		"%s: the character and its shadow reach %.0f px at most from it (limit %.0f)" % [
			spot["name"], far, REACH],
	)
	if shot != "":
		print("CHARSHADOW %s reach=%.0f changed=%d" % [spot["name"], far, changed])


## What the character changes in four pictures taken hidden, shown, hidden, shown: the pixels both
## shown ones have and both hidden ones lack (a light that flickers or fades in between breaks one
## of them): `(how many, how far from the middle in world px)`.
func _changed(p: Array[Image]) -> Vector2:
	var far := 0.0
	var changed := 0
	var middle := Vector2(SIZE) * 0.5
	for y in SIZE.y:
		for x in SIZE.x:
			var ha := p[0].get_pixel(x, y)
			var sa := p[1].get_pixel(x, y)
			var hb := p[2].get_pixel(x, y)
			var sb := p[3].get_pixel(x, y)
			if _differs(ha, hb) or _differs(sa, sb):
				continue
			if _differs(sa, ha) and _differs(sa, hb):
				changed += 1
				far = maxf(far, (Vector2(x, y) - middle).length() / 2.0)
	return Vector2(changed, far)


## The drop shadow is seen: the pixels round the character are darker with its patch than with the
## patch hidden (the body the same), as the 2D body's floor shadow is.
func _check_patch_shows(
	t: TestContext, person: Node2D, spot: Dictionary, with: Image
) -> void:
	var shown: Array = (_view.carrier as MeshCarrier).proxies_of(person)
	var patch: Node3D = null
	if not shown.is_empty():
		patch = (shown[0] as Node).get_node_or_null("DropShadow")
	if not t.require(patch != null, "%s: the body has a drop shadow" % spot["name"]):
		return
	patch.visible = false
	var hidden := await _draw(t, spot["at"], 2.0)
	patch.visible = true
	var span := int(person.radius * 2.0 * 2.0)
	var middle := Vector2i(SIZE / 2)
	var light_with := 0.0
	var light_hidden := 0.0
	for y in range(middle.y - span, middle.y + span):
		for x in range(middle.x - span, middle.x + span):
			light_with += with.get_pixel(x, y).get_luminance()
			light_hidden += hidden.get_pixel(x, y).get_luminance()
	t.check(
		light_with < light_hidden * (1.0 - PATCH_DARKER),
		"%s: the drop shadow darkens the floor round the body (%.1f with, %.1f without)" % [
			spot["name"], light_with, light_hidden,
		],
	)


## Save `image` as `<CHARSHADOW_DIR>/<name>.png`; the path, "" when none is asked for.
func _save(image: Image, name: String) -> String:
	var dir := OS.get_environment("CHARSHADOW_DIR")
	if dir == "":
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.png" % [dir, name]
	image.save_png(path)
	return path


func _differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > CHANGED
