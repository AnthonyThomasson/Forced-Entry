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
## Then, at the first yaw, with the ceiling fixtures' shadows on (held still for the reading):
##
## - a mover on the cone's edge is cut there, pixel by pixel: some of it is drawn on the lit side
##   and none beyond the cut (`MeshNodes.moving`, the shader's discard);
## - a thing that moves just outside the cone (a tall box marked `MeshNodes.moving`: a character
##   casts no shadow, a vehicle does) casts no shadow on the lit floor inside the cone: freeing it
##   changes the floor there not at all, while freeing one drawn in the cone does (so the probe can
##   see a shadow).
##
## The yaws are run at every quarter and again at the camera's other zooms (0.5 and 3).
##
## Environment: `VISION_DIR` saves the pictures (`mask_<phase>_<yaw>.png`), `VISION_YAWS`
## (default `0,90,180,270`) the camera yaws, `VISION_PLAN` the house plan, `VISION_SEED`.
## Run: `tools/run_tests.sh --windowed --id=vision/vision_mask_3d_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const CharacterScene := preload("res://scenes/character/character_base.tscn")
const SCRATCH := "user://settings_vision_mask_3d_windowed_test.json"
const SIZE := Vector2i(1152, 648)
## The characters stand this far (px) east and west of the human; the floor probes are beside them.
const SPREAD := 170.0
## The camera's zoom steps run again at yaw 0: offsets from its own step (1x): 0.5x and 3x.
const ZOOM_OFFSETS: Array[int] = [-1, 2]
## A mover's height (px), for how far its shadow falls.
const MOVER_HEIGHT := 36.0
## The shadow's layout (`_layout`): the box's distance from the lamp (px), and where the human
## stands against the shadow's end (px along the line past it, px to the side of it).
const LAMP_GAP := 40.0
const ALONG := 10.0
const AHEAD := 30.0
## The cut: a mover is drawn where the live mask reads at least this (the shader's 0.5, less the
## width of a pixel's sampling), and a pixel it changes where the mask reads under `LEAK` is drawn
## beyond the cut.
const DRAWN_FROM := 0.6
const LEAK := 0.4
## A shadow here is the shadow of the box's top, a block as wide as the box (`_tall_box`) about the
## spot it falls on: the pixels within `SHADOW_REACH` of it that change by `SHADOW_STEP` are
## counted; a shadow is at least `MIN_SHADOW` of them, none at most `MAX_SHADOW`.
const SHADOW_REACH := 14
const SHADOW_STEP := 0.04
const MIN_SHADOW := 20
const MAX_SHADOW := 2
const MIN_DRAWN := 8
const MAX_LEAKED := 2
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
var _room := Rect2()
var _yaws: Array[float] = [0.0, 90.0, 180.0, 270.0]
var _camera: Camera2D
var _mask: Image
var _window_rect := Rect2()


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
		await _at_yaw(t, i == 0, "yaw%d" % int(_yaws[i]))
		if i == 0:
			await _straddle(t)
			await _shadow(t)
	_rig.yaw = _yaws[0]
	for offset in ZOOM_OFFSETS:
		_zoom(offset)
		await _look(t, Vector2.RIGHT, TURN_FRAMES)
		await _at_yaw(t, false, "yaw%d_zoom%.1f" % [int(_yaws[0]), _camera.zoom.x], true)
	_zoom(0)
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
	_camera = Camera2D.new()
	_camera.name = "MainCamera"
	_camera.set_script(CameraScript)
	_main.add_child(_camera)
	_camera.make_current()
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
	_room = room
	_centre = room.get_center()
	_human.global_position = _centre
	return true


## One camera yaw: the three phases and their checks (what is unseen only at the first yaw: after
## it the human has looked about; `zoomed` is a run at another zoom, whose probes are nearer the
## human).
func _at_yaw(t: TestContext, first: bool, tag: String, zoomed := false) -> void:
	var near := clampf(1.2 / _camera.zoom.x, 0.3, 1.0)  # a zoomed-in view shows less of the room
	var east := _stand(_centre + Vector2(SPREAD * near, 0.0))
	var west := _stand(_centre + Vector2(-SPREAD * near, 0.0))
	await _look(t, Vector2.RIGHT, SETTLE_FRAMES)
	var lit := _patch(_centre + IN_VIEW_PROBE * near)
	var black := _patch(_centre + BEHIND_PROBE * near)
	_save("in_view", tag)
	t.check(
		lit.get_luminance() >= MIN_LIT,
		"%s: the floor in the cone is lit (%s)" % [tag, lit],
	)
	if first:
		t.check(
			black.get_luminance() <= MAX_BLACK,
			"%s: the floor behind, never seen, is black (%s)" % [tag, black],
		)
		var leak := _brightest_in_strip()
		t.check(
			leak <= MAX_BLACK,
			"%s: no wall or furniture of the unseen house shows (brightest %.3f)" % [tag, leak],
		)
	await _drawn(t, east, "%s: the character in the cone" % tag, true)
	# Look west and back: the floor behind is remembered.
	await _look(t, Vector2.LEFT, LOOK_FRAMES)
	_save("looking_back", tag)
	await _look(t, Vector2.RIGHT, LOOK_FRAMES)
	var remembered := _patch(_centre + BEHIND_PROBE * near)
	var again := _patch(_centre + IN_VIEW_PROBE * near)
	_save("memory", tag)
	t.check(
		remembered.get_luminance() >= MIN_REMEMBERED,
		"%s: seen floor behind is not black (%s)" % [tag, remembered],
	)
	if not zoomed:  # a zoomed view's probes lie on different floors (the bedroom's is lighter)
		t.check(
			remembered.get_luminance() <= again.get_luminance() * MAX_REMEMBERED,
			"%s: and dimmer than the floor in view (%s, %s)" % [tag, remembered, again],
		)
	var tint := maxf(remembered.r, maxf(remembered.g, remembered.b)) - minf(
		remembered.r, minf(remembered.g, remembered.b)
	)
	t.check(tint <= MAX_TINT, "%s: and nearly grey (spread %.3f)" % [tag, tint])
	await _drawn(t, west, "%s: the character on the remembered floor" % tag, false)


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


func _image_patch(at: Vector2, radius := PATCH) -> Color:
	var image := _window.get_texture().get_image()
	var centre := Vector2i(Pointer.screen_of(_world, at).round())
	var sum := Color(0, 0, 0, 0)
	var count := 0
	for y in range(centre.y - radius, centre.y + radius + 1):
		for x in range(centre.x - radius, centre.x + radius + 1):
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


## Save the picture as `mask_<phase>_<tag>.png` under `VISION_DIR` (nothing when it is unset).
func _save(phase: String, tag: String) -> void:
	var dir := OS.get_environment("VISION_DIR")
	if dir == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	RenderingServer.force_draw(false)
	_window.get_texture().get_image().save_png("%s/mask_%s_%s.png" % [dir, phase, tag])


## The house's largest room, a world rect.
func _largest_room(house: Node2D) -> Rect2:
	var best := Rect2()
	for room: Dictionary in WorldGen.get_rooms(house):
		var rect: Rect2 = room["rect"]
		if rect.get_area() > best.get_area():
			best = rect
	return best


## The camera's zoom `steps` steps off its own (a whole step: 0 is 1x, -1 is 0.5x, 2 is 3x).
func _zoom(steps: int) -> void:
	var held: Variant = _camera.get("_steps")
	held.offset = steps


## The view of the human (null when there is none).
func _view() -> PlayerView:
	return _world.find_child("PlayerView", true, false) as PlayerView


## Read the live mask as it is drawn now.
func _read_mask() -> void:
	var ground := _view().ground
	_mask = ground.live.get_texture().get_image()
	_window_rect = ground.window


## What the live mask holds (red, 0 to 1) at the world point `at`; 0 off the window.
func _mask_at(at: Vector2) -> float:
	var uv := (at - _window_rect.position) / _window_rect.size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return 0.0
	return _mask.get_pixelv(Vector2i(uv * Vector2(_mask.get_size()))).r


## The point of the cone's lower edge, `across` px east of the human, where the live mask crosses
## `level` going outward (south); INF when there is no edge there (a wall cut the cone first: the
## edge is the one of the cone's 110 degrees, so its slope is the tangent of 55).
func _edge_point(across: float, level: float) -> Vector2:
	var x := _centre.x + across
	for step in range(0, 600):
		var at := Vector2(x, _centre.y + float(step))
		if _mask_at(at) < level:
			var slope := (at.y - _centre.y) / across
			return at if absf(slope - tan(deg_to_rad(55.0))) < 0.3 else Vector2.INF
	return Vector2.INF


## A mover on the cone's edge is cut there: some of it is drawn on the lit side, none beyond.
func _straddle(t: TestContext) -> void:
	await _look(t, Vector2.RIGHT, SETTLE_FRAMES)
	RenderingServer.force_draw(false)
	_read_mask()
	var edge := Vector2.INF
	for across in [100.0, 80.0, 120.0, 60.0, 140.0]:
		edge = _edge_point(across, 0.5)
		if edge != Vector2.INF:
			break
	if not t.require(edge != Vector2.INF, "premise: the cone's edge is in the room"):
		return
	var mover := _stand(edge)
	await t.frames(3)
	RenderingServer.force_draw(false)
	var with := _window.get_texture().get_image()
	mover.queue_free()
	await t.frames(3)
	RenderingServer.force_draw(false)
	var without := _window.get_texture().get_image()
	var drawn := 0
	var leaked := 0
	for dy in range(-24, 25):
		for dx in range(-24, 25):
			var at := edge + Vector2(dx, dy)
			var px := Vector2i(Pointer.screen_of(_world, at).round())
			if not Rect2i(Vector2i.ZERO, with.get_size()).has_point(px):
				continue
			if _distance(with.get_pixelv(px), without.get_pixelv(px)) < DIFFERS:
				continue
			var read := _mask_at(at)
			if read >= DRAWN_FROM:
				drawn += 1
			elif read < LEAK:
				leaked += 1
	t.check(
		drawn >= MIN_DRAWN,
		"a mover on the cone's edge is drawn on the lit side (%d px)" % drawn,
	)
	t.check(leaked <= MAX_LEAKED, "and cut at the edge: %d px drawn beyond it" % leaked)


## A moving thing just outside the cone casts no shadow on the lit floor inside it. A box stands
## outside the cone and a ceiling fixture throws the shadow of its top across the cone's edge, its
## end inside the cone: nothing changes there when the box is taken away. Then the human turns to
## the box, so the same box and the same spot of floor are in the cone: now taking it away does
## change the floor (so the spot shows a shadow at all, and is not already in the shade of a wall).
## The lights are held still while the floor is read (they flicker).
func _shadow(t: TestContext) -> void:
	var layout := await _find_layout(t)
	if not t.require(
		not layout.is_empty(),
		"premise: a box outside the cone, its shadow ending in",
	):
		_human.global_position = _centre
		return
	var spot: Vector2 = layout["spot"]
	var tip: Vector2 = layout["tip"]
	var lighting := _main.get_node("View3D").lighting as WorldLighting3D
	lighting.process_mode = Node.PROCESS_MODE_DISABLED
	var hidden_change := await _floor_changed(t, spot, tip, "outside")
	t.check(
		hidden_change <= MAX_SHADOW,
		"a box that moves outside the cone casts no shadow on the floor (%d px)" % hidden_change,
	)
	await _look(t, (spot + tip) * 0.5 - (layout["stand"] as Vector2), SETTLE_FRAMES)
	RenderingServer.force_draw(false)
	_read_mask()
	t.require(
		_mask_at(spot) >= 0.9 and _mask_at(tip) >= 0.9,
		"premise: turned to it, the box and the end of its shadow are in the cone",
	)
	var seen_change := await _floor_changed(t, spot, tip, "in_cone")
	t.check(
		seen_change >= MIN_SHADOW,
		"premise: the same box in the cone casts a shadow the floor shows (%d px)" % seen_change,
	)
	lighting.process_mode = Node.PROCESS_MODE_INHERIT
	_human.global_position = _centre
	await _look(t, layout["facing"], SETTLE_FRAMES)


## The first layout (`_layout`) of any shadow-casting fixture, any direction and side, that the
## live mask confirms once the human stands there: the box outside the cone, the end inside it.
## The human is left standing there; empty for none.
func _find_layout(t: TestContext) -> Dictionary:
	for lamp in _lamps():
		for along in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			for side in [-1.0, 1.0]:
				var layout := _layout(lamp, along, side)
				if layout.is_empty():
					continue
				_human.global_position = layout["stand"]
				await _look(t, layout["facing"], SETTLE_FRAMES)
				RenderingServer.force_draw(false)
				_read_mask()
				var spot: Vector2 = layout["spot"]
				if (
					_mask_at(spot) <= 0.02
					and _lit_around(layout["tip"])
					and not SeenArea.reaches(spot, 10.0)
				):
					return layout
	return {}


## The ceiling fixtures that cast a shadow, nearest the room's middle first: each its x and z in
## world px and its height above the floor (px).
func _lamps() -> Array[Vector3]:
	var found: Array[Vector3] = []
	var fixtures: Array = (_main.get_node("View3D").lighting as WorldLighting3D).fixtures()
	for fixture: Dictionary in fixtures:
		var lamp: OmniLight3D = fixture["light"]
		if lamp.shadow_enabled:
			found.append(lamp.global_position / RenderConfig.unit)
	found.sort_custom(
		func(a: Vector3, b: Vector3) -> bool:
			return Vector2(a.x, a.z).distance_to(_centre) < Vector2(b.x, b.z).distance_to(_centre)
	)
	return found


## Where to stand the box and the human so the lamp's shadow of the box's top runs across the cone's
## edge: the box `LAMP_GAP` px from the lamp along `along`, its shadow's end `fall` px further on,
## the human looking sideways (`side` of the line, `AHEAD` px from it) from just past the end, so
## the end is within `ALONG` px of the line of sight and the box a good way off it. Empty when
## something solid is in the way.
func _layout(lamp: Vector3, along: Vector2, side: float) -> Dictionary:
	var at := Vector2(lamp.x, lamp.z)
	var fall := LAMP_GAP * MOVER_HEIGHT / (lamp.y - MOVER_HEIGHT)
	var spot := at + along * LAMP_GAP
	var tip := spot + along * fall
	var facing := along.rotated(side * PI * 0.5)
	var stand := tip + along * ALONG - facing * AHEAD
	for point in [spot, tip, stand, (spot + tip) * 0.5]:
		if not _bare(point):
			return {}
	return { "spot": spot, "tip": tip, "stand": stand, "facing": facing }


## Whether nothing solid (a wall, a piece of furniture) stands within 18 px of `at`: a shadow that
## falls there falls on the floor, not on a table top.
func _bare(at: Vector2) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, at)
	query.exclude = [_human.get_rid()]
	return _world.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


## Whether the live mask is whole (lit) round `at`, a few px each way.
func _lit_around(at: Vector2) -> bool:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		offsets.append(dir * 12.0)
	for off in offsets:
		if _mask_at(at + off) < 0.95:
			return false
	return true


## How many pixels of the picture within `SHADOW_REACH` px of the world point `tip` (where the
## shadow of the box's top falls) change when a tall box that moves (`MeshNodes.moving`, as a
## vehicle is: a character casts no shadow) standing at `at` is taken away.
func _floor_changed(t: TestContext, at: Vector2, tip: Vector2, tag: String) -> int:
	var box := MeshNodes.instance(_tall_box(), Color(0.8, 0.75, 0.7))
	MeshNodes.moving(box)
	box.position = Vector3(at.x, MOVER_HEIGHT * 0.5, at.y) * RenderConfig.unit
	var stage: Node3D = _main.get_node("View3D").mirror
	stage.add_child(box)
	await t.frames(3)
	_draw_twice()  # a node added shows in the second draw (its shadow too)
	var with := _window.get_texture().get_image()
	_save("shadow_with", tag)
	box.queue_free()
	await t.frames(3)
	_draw_twice()
	var without := _window.get_texture().get_image()
	_save("shadow_without", tag)
	var centre := Vector2i(Pointer.screen_of(_world, tip).round())
	var changed := 0
	for y in range(centre.y - SHADOW_REACH, centre.y + SHADOW_REACH + 1):
		for x in range(centre.x - SHADOW_REACH, centre.x + SHADOW_REACH + 1):
			if not Rect2i(Vector2i.ZERO, with.get_size()).has_point(Vector2i(x, y)):
				continue
			if _distance(with.get_pixel(x, y), without.get_pixel(x, y)) >= SHADOW_STEP:
				changed += 1
	return changed


## The window drawn now, and once more: what changed is in the second.
func _draw_twice() -> void:
	for _i in 4:
		RenderingServer.force_draw(false)


## A box `MOVER_HEIGHT` tall and 16 px each way, in 3D units.
func _tall_box() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(16.0, MOVER_HEIGHT, 16.0) * RenderConfig.unit
	return mesh
