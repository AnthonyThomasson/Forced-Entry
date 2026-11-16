extends GameTest
## The player's view in the 3D render, drawn (#193 vision-mask, windowed only: the headless renderer
## draws nothing and compiles no shader, so a wrong mask, uv or look shows only here). Main is run
## whole over a played 3D match in a window, the human alone in the house's largest room facing
## east, a character east of it in the cone and one west of it behind. At each camera yaw (a turn
## puts the mask's world-to-uv map through every orientation):
##
## - in view: the floor in the cone is lit, and the character in the cone is drawn (taking it away
##   changes the picture there);
## - unseen: the floor behind it, never seen, is black;
## - memory: after the human looks west and back east, that floor is remembered: dimmer than the
##   floor in view, not black, and nearly grey, and the character that stands on it is not drawn
##   (taking it away changes nothing there): a thing that moves is drawn only in the cone.
##
## Environment: `VISION_DIR` saves the pictures (`mask_<phase>_yaw<yaw>.png`), `VISION_YAWS`
## (default `0,90`) the camera yaws, `VISION_PLAN` the house plan, `VISION_SEED`.
## Run: `tools/run_tests.sh --windowed --id=vision/vision_mask_3d_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const CharacterScene := preload("res://scenes/character/character_base.tscn")
const SCRATCH := "user://settings_vision_mask_3d_windowed_test.json"
const SIZE := Vector2i(1152, 648)
## The characters stand this far (px) east and west of the human; the floor probes are beside them.
const SPREAD := 170.0
const IN_VIEW_PROBE := Vector2(100.0, 50.0)
const BEHIND_PROBE := Vector2(-100.0, 50.0)
## A probe is the mean of the picture this many pixels each side of its point.
const PATCH := 7
## Frames for the camera to settle on the human, for a turn of the view, for a look to sweep.
const SETTLE_FRAMES := 40
const TURN_FRAMES := 60
const LOOK_FRAMES := 45
## What the picture must show (luminance 0 to 1): the floor in view is at least this bright; floor
## never seen at most this; a remembered floor is this much of the floor in view at most and at
## least `MIN_REMEMBERED`, and its colour spread (max minus min channel) at most `MAX_TINT`.
const MIN_LIT := 0.12
const MAX_BLACK := 0.03
const MAX_REMEMBERED := 0.85
const MIN_REMEMBERED := 0.02
const MAX_TINT := 0.12
## The width (px) of the picture's left strip, where nothing has been seen.
const STRIP := 100
## Taking a character away changes its patch by at least this (mean channel difference) when it
## was drawn and by at most `SAME` when it was not.
const DIFFERS := 0.02
const SAME := 0.006

var _window: SubViewport
var _main: Node
var _human: CharacterBody2D
var _world: Node2D
var _rig: CameraRig
var _centre := Vector2.ZERO
var _yaws: Array[float] = [0.0, 90.0]


func describe() -> Dictionary:
	return {
		"name": "The 3D view lights the cone, remembers, and hides what it does not see (windowed)",
		"description": "A played 3D match in a window, the human in a room: the floor in the cone "
			+ "is lit and a character there drawn, the floor behind it never seen is black, and "
			+ "once seen it is remembered dim and grey with the character standing on it not "
			+ "drawn, at each camera yaw. Windowed only.",
		"tags": ["vision", "render", "3d", "windowed"],
		"timeout": 240.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"render_mode", Settings.RENDER_2D)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.set_static(GroundLayer, &"enabled", false)
	s.switch(&"vision.enabled", true)
	s.von_script([])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	_read_environment()
	if not await _start(t):
		return
	for i in _yaws.size():
		_rig.yaw = _yaws[i]
		await _look(t, Vector2.RIGHT, TURN_FRAMES)
		await _at_yaw(t, _yaws[i], i == 0)
	await MainProbe.close(t, _window)


func _read_environment() -> void:
	var text := OS.get_environment("VISION_YAWS")
	if text != "":
		_yaws = []
		for part: String in text.split(",", false):
			_yaws.append(float(part))


## The window and the match, the human alone in the largest room; false when that failed.
func _start(t: TestContext) -> bool:
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
	var plan := OS.get_environment("VISION_PLAN")
	_human = _main.get_node("Player")
	var spec := {
		"render": Settings.RENDER_3D,
		"seed": maxi(int(OS.get_environment("VISION_SEED")), 2),
		"plan": plan if plan != "" else "starter_home",
		"defenders": { "count": 1 },
		"invaders": { "count": 1 },
		"human": { "node": _human, "side": &"invader", "lead": false },
	}
	var built: Dictionary = await _main.start_match(spec)
	if not t.require(not built.is_empty(), "a played match started in 3D"):
		return false
	_world = built["world"]
	_rig = _main.get_node("View3D").rig
	for body: Node in _world.find_children("*", "CharacterBody2D", true, false):
		if body != _human:
			(body as Node2D).global_position = Vector2(-6000.0, -6000.0)
	var room := _largest_room(built["house"])
	t.check(room.size.x >= SPREAD * 2.0 + 60.0, "premise: a room wide enough (%s)" % room)
	_centre = room.get_center()
	_human.global_position = _centre
	return true


## One camera yaw: the three phases and their checks (what is unseen only at the first yaw: after
## it the human has looked about).
func _at_yaw(t: TestContext, yaw: float, first: bool) -> void:
	var east := _stand(_centre + Vector2(SPREAD, 0.0))
	var west := _stand(_centre + Vector2(-SPREAD, 0.0))
	await _look(t, Vector2.RIGHT, SETTLE_FRAMES)
	var lit := _patch(_centre + IN_VIEW_PROBE)
	var black := _patch(_centre + BEHIND_PROBE)
	_save("in_view", yaw)
	t.check(
		lit.get_luminance() >= MIN_LIT,
		"yaw %d: the floor in the cone is lit (%s)" % [yaw, lit],
	)
	if first:
		t.check(
			black.get_luminance() <= MAX_BLACK,
			"yaw %d: the floor behind, never seen, is black (%s)" % [yaw, black],
		)
		var leak := _brightest_in_strip()
		t.check(
			leak <= MAX_BLACK,
			"yaw %d: no wall or furniture of the unseen house shows (brightest %.3f)" % [yaw, leak],
		)
	await _drawn(t, east, "yaw %d: the character in the cone" % yaw, true)
	# Look west and back: the floor behind is remembered.
	await _look(t, Vector2.LEFT, LOOK_FRAMES)
	_save("looking_back", yaw)
	await _look(t, Vector2.RIGHT, LOOK_FRAMES)
	var remembered := _patch(_centre + BEHIND_PROBE)
	var again := _patch(_centre + IN_VIEW_PROBE)
	_save("memory", yaw)
	t.check(
		remembered.get_luminance() >= MIN_REMEMBERED,
		"yaw %d: seen floor behind is not black (%s)" % [yaw, remembered],
	)
	t.check(
		remembered.get_luminance() <= again.get_luminance() * MAX_REMEMBERED,
		"yaw %d: and dimmer than the floor in view (%s, %s)" % [yaw, remembered, again],
	)
	var tint := maxf(remembered.r, maxf(remembered.g, remembered.b)) - minf(
		remembered.r, minf(remembered.g, remembered.b)
	)
	t.check(tint <= MAX_TINT, "yaw %d: and nearly grey (spread %.3f)" % [yaw, tint])
	await _drawn(t, west, "yaw %d: the character on the remembered floor" % yaw, false)


## `who` drawn (taking it away changes its patch) or not (it does not), then freed.
func _drawn(t: TestContext, who: Node2D, what: String, expected: bool) -> void:
	var at := who.global_position
	var before := _image_patch(at)
	who.queue_free()
	await t.frames(3)
	RenderingServer.force_draw(false)
	var after := _image_patch(at)
	var change := _distance(before, after)
	if expected:
		t.check(change >= DIFFERS, "%s is drawn (changes the picture by %.3f)" % [what, change])
	else:
		t.check(change <= SAME, "%s is not drawn (changes the picture by %.3f)" % [what, change])


## A character with no brain at `at`, in a plain outfit, facing the human.
func _stand(at: Vector2) -> CharacterBody2D:
	var c := CharacterScene.instantiate() as CharacterBody2D
	c.global_position = at
	_world.add_child(c)
	c.movement.controller = null
	c.movement.move_input = Vector2.ZERO
	c.health = 1.0e9
	c.wardrobe.outfit.set_ids(
		{ "body": &"tshirt", "pants": &"jeans", "feet": &"shoes", "head": &"hat" }
	)
	c.movement.aim_point = _centre
	return c


## The human faces along `dir` for `frames` frames (the pointer is held on a point that way).
func _look(t: TestContext, dir: Vector2, frames: int) -> void:
	for _i in frames:
		Pointer.inject(Pointer.screen_of(_world, _human.global_position + dir * 300.0))
		await t.frames(1)


## The mean colour of the patch round the world point `at`, drawn now.
func _patch(at: Vector2) -> Color:
	RenderingServer.force_draw(false)
	return _image_patch(at)


func _image_patch(at: Vector2) -> Color:
	var image := _window.get_texture().get_image()
	var centre := Vector2i(Pointer.screen_of(_world, at).round())
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for y in range(centre.y - PATCH, centre.y + PATCH + 1):
		for x in range(centre.x - PATCH, centre.x + PATCH + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				sum += image.get_pixel(x, y)
				count += 1
	return sum / float(maxi(count, 1))


## The brightest luminance in the picture's left strip, houses away from the human: never seen.
func _brightest_in_strip() -> float:
	var image := _window.get_texture().get_image()
	var brightest := 0.0
	for y in image.get_height():
		for x in STRIP:
			brightest = maxf(brightest, image.get_pixel(x, y).get_luminance())
	return brightest


func _distance(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0


## Save the picture as `mask_<phase>_yaw<yaw>.png` under `VISION_DIR` (nothing when it is unset).
func _save(phase: String, yaw: float) -> void:
	var dir := OS.get_environment("VISION_DIR")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	_window.get_texture().get_image().save_png("%s/mask_%s_yaw%d.png" % [dir, phase, int(yaw)])


## The house's largest room, a world rect.
func _largest_room(house: Node2D) -> Rect2:
	var best := Rect2()
	for room: Dictionary in WorldGen.get_rooms(house):
		var rect: Rect2 = room["rect"]
		if rect.get_area() > best.get_area():
			best = rect
	return best
