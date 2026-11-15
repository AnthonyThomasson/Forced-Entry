extends GameTest
## How the pixel post's outline treats a character at the game's zoom (windowed only: the headless
## renderer draws nothing and compiles no shader; #193 phase 2, Art, interface 27). A Watch match
## started with 3D chosen, the camera over one of its characters: the log gate fails the test on
## any shader or engine error, and the picture is checked for the one thing the outline must not
## do, bury a body: at zoom 1 (a character about 25 px, one or two internal pixels a limb) the
## share of near-black pixels over the body is small, and smaller than with the creases and the
## one near-black line the outline had. The look itself is judged by eye: with `OUTLINE_SHOTS=<dir>`
## set it saves the shots (standing, facing away, crouched, in a vest, beside walls; at zoom 3 and
## 1) as they are now, `before_` the same with the old line (one near-black colour, creases on the
## figure). Run: `tools/run_tests.sh --windowed --id=art/pixel_post_outline_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const SCRATCH := "user://settings_pixel_post_outline_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"defenders": { "count": 2 },
	"invaders": { "count": 2 },
}
## The zooms of the shots: close, and the game's default.
const ZOOMS := [3.0, 1.0]
## A pixel darker than this (luminance) is near-black: what a body buried in outline is made of.
const BLACK := 0.12
## The window round the character (screen px) whose near-black share is counted at zoom 1.
const BODY_BOX := 30
## The box over a standing character at zoom 1 (screen px from the picture's centre, where the
## camera is over it: the body, 74 px tall, seen from the 80 degrees above, about 30 by 40 px), and
## how many pixels differ with the creases off: at least this many of the world's, at most this many
## over the body. A body's textured art can move by a pixel between shots (a sleeve's plate lines
## shift with the sub-pixel breath), so a pixel that also differs between two shots with the same
## settings is not a crease and is not counted.
const FIGURE_BOX := Rect2i(-18, -26, 38, 52)
const WORLD_CREASES := 100
const BODY_CREASES := 9

## What a shot is taken with: the window, the camera over the character, the character and the
## outline quad of the view (set by `run`).
var _window: SubViewport
var _camera: Camera2D
var _character: Node2D
var _quad: MeshInstance3D
var _oversample := 1


func describe() -> Dictionary:
	return {
		"name": "A character at zoom 1 is not buried in outline (windowed)",
		"description": "A 3D Watch match, the camera over a character at zoom 1: the near-black "
			+ "share of the body's pixels stays small and below what the old fixed line and "
			+ "creased facets gave. Windowed only.",
		"tags": ["render", "3d", "windowed", "pixel", "character"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_3D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(PixelPostConfig, &"outline_darken", PixelPostConfig.outline_darken)
	s.set_static(PixelPostConfig, &"figure_darken", PixelPostConfig.figure_darken)
	s.set_static(PixelPostConfig, &"figure_creases", PixelPostConfig.figure_creases)
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
	_window = window
	_camera = camera
	_character = character
	_quad = view.rig.camera.get_node(PixelPost.NODE) as MeshInstance3D
	_oversample = view.rig.oversample
	_character.movement.controller = null
	_character.movement.move_input = Vector2.ZERO
	_character.movement.aim_point = character.global_position + Vector2(200.0, 200.0)
	await t.seconds(0.6)
	var now := await _round(t, "", true)
	_check_buried(t, now, await _round(t, "before_", false))
	await _check_creases(t)
	await MainProbe.close(t, window)


## The body is not buried in near-black, as it was with the old line.
func _check_buried(t: TestContext, now: Dictionary, old: Dictionary) -> void:
	t.check(
		now["black"] < 0.1,
		"at zoom 1 under 10%% of the body's pixels are near-black (%.2f)" % now["black"],
	)
	t.check(
		now["black"] < old["black"],
		"fewer than with the old line: %.2f against %.2f" % [now["black"], old["black"]],
	)
	t.check(now["colours"] > old["colours"], "and more colours: %d against %d" % [
		now["colours"], old["colours"],
	])


## The creases are drawn on the world and not on the figure: the same standing shot at zoom 1 with
## creases and with none (`normal_step` far above any difference of normals) differs, beyond the
## body, where walls and furniture meet at an edge (a flag read as set on every pixel would lose
## them), and does not differ over the body (the silhouette is all that outlines it).
func _check_creases(t: TestContext) -> void:
	_character.movement.set_posture(&"stand")
	_character.movement.aim_point = _character.global_position + Vector2(200.0, 200.0)
	await t.seconds(0.6)
	# The game's time stopped, so the breath does not move the body between the two shots.
	Engine.time_scale = 0.0001
	var creased := await _shoot(t, 1.0)
	var again := await _shoot(t, 1.0)
	var normal_step := PixelPostConfig.normal_step
	PixelPostConfig.normal_step = 100.0
	PixelPost.refresh(_quad, _oversample)
	var plain := await _shoot(t, 1.0)
	Engine.time_scale = 1.0
	PixelPostConfig.normal_step = normal_step
	PixelPost.refresh(_quad, _oversample)
	_save(creased, "creased_zoom1")
	_save(plain, "plain_zoom1")
	var centre := creased.get_size() / 2
	var body := Rect2i(centre + FIGURE_BOX.position, FIGURE_BOX.size)
	var on_body := 0
	var on_world := 0
	for y in creased.get_height():
		for x in creased.get_width():
			if creased.get_pixel(x, y) == plain.get_pixel(x, y):
				continue
			if not body.has_point(Vector2i(x, y)):
				on_world += 1
			elif creased.get_pixel(x, y) == again.get_pixel(x, y):
				on_body += 1  # a pixel that moved between two like shots is jitter, not a crease
	t.check(
		on_world >= WORLD_CREASES,
		"the world keeps its creases: %d pixels differ beyond the body" % on_world,
	)
	t.check(
		on_body <= BODY_CREASES,
		"the body has none: %d pixels differ over it" % on_body,
	)


## The shots of one look of the outline (`now`: the holder's, else the old line), the body's
## numbers at zoom 1 standing.
func _round(t: TestContext, prefix: String, now: bool) -> Dictionary:
	var darken := PixelPostConfig.outline_darken
	var figure_darken := PixelPostConfig.figure_darken
	var creases := PixelPostConfig.figure_creases
	if not now:
		PixelPostConfig.outline_darken = 0.0
		PixelPostConfig.figure_darken = 0.0
		PixelPostConfig.figure_creases = true
	PixelPost.refresh(_quad, _oversample)
	_character.movement.set_posture(&"stand")
	var numbers := {}
	for look: String in ["", "away_"]:
		var toward := Vector2(1, 1) if look == "" else Vector2(-1, -1)
		_character.movement.aim_point = _character.global_position + toward * 200.0
		await t.seconds(0.5)
		for zoom: float in ZOOMS:
			var image := await _shoot(t, zoom)
			_save(image, "%sstanding_%szoom%d" % [prefix, look, int(zoom)])
			if look == "" and zoom == 1.0:
				numbers = _body_numbers(image)
	var wardrobe: CharacterWardrobe = _character.wardrobe
	var worn: Dictionary = wardrobe.outfit.ids().duplicate()
	wardrobe.outfit.set_ids({
		"vest": &"plate_carrier", "front_plate": &"ceramic_iv", "body": &"shirt",
	})
	await t.seconds(0.4)
	for zoom: float in ZOOMS:
		_save(
			await _shoot(t, zoom),
			"%svest_zoom%d" % [prefix, int(zoom)],
		)
	wardrobe.outfit.set_ids(worn)
	_character.movement.set_posture(&"crouch")
	await t.seconds(0.8)
	for zoom: float in ZOOMS:
		_save(
			await _shoot(t, zoom),
			"%scrouched_zoom%d" % [prefix, int(zoom)],
		)
	PixelPostConfig.outline_darken = darken
	PixelPostConfig.figure_darken = figure_darken
	PixelPostConfig.figure_creases = creases
	PixelPost.refresh(_quad, _oversample)
	return numbers


## Park the camera over `character` at `zoom` and the picture the window then shows.
func _shoot(t: TestContext, zoom: float) -> Image:
	_camera.zoom = Vector2(zoom, zoom)
	_camera.global_position = _character.global_position
	await t.frames(8)
	await RenderingServer.frame_post_draw
	return _window.get_texture().get_image()


## Save `image` as `<name>.png` in the folder `OUTLINE_SHOTS` names (nothing when it is unset).
func _save(image: Image, name: String) -> void:
	var folder := OS.get_environment("OUTLINE_SHOTS")
	if folder != "":
		DirAccess.make_dir_recursive_absolute(folder)
		image.save_png("%s/%s.png" % [folder, name])


## The near-black share and the distinct colours of the pixels of the box round the picture's
## centre (the character, which the camera is over), at zoom 1.
func _body_numbers(image: Image) -> Dictionary:
	var centre := image.get_size() / 2
	var seen := {}
	var black := 0
	var total := 0
	for y in range(centre.y - BODY_BOX, centre.y + BODY_BOX):
		for x in range(centre.x - BODY_BOX, centre.x + BODY_BOX):
			var colour := image.get_pixel(x, y)
			total += 1
			seen[colour.to_rgba32()] = true
			if colour.get_luminance() < BLACK:
				black += 1
	return { "black": float(black) / float(total), "colours": seen.size() }


## The first living character the match built; nobody dies while the shots are taken.
func _first_character(world: Node) -> CharacterBody2D:
	var bodies := world.find_children("*", "CharacterBody2D", true, false)
	for body: Node in bodies:
		body.set("health", 1.0e9)
	for body: Node in bodies:
		if not body.get("is_dead"):
			return body as CharacterBody2D
	return null
