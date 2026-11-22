extends GameTest
## A shop or special-room item reads as bright and as colourful as the drawing it replaced in the
## lit 3D picture, in a real window (windowed only: the headless renderer draws nothing; #194
## unbake-c, D21 "the old look kept", `docs/stacked-items.md` SI16). A played 3D match (garage_home,
## seed 2); for each of the till, jar, pack, pot, bowl, instruments, syringe and the cyberware (the
## bottles and snacks are lit by the glow of the fridge or machine they stand in, so one alone is
## no fair pair), the OLD drawing (`tests/_art/old_shop_look.gd`, the painters' code of 08f43a10 on
## a flat textured sheet, as the painted top lit it) and then the NEW item (`PieceCarries.patched`
## from the row that carries it) stand at the SAME spot under the same camera, one after the
## other, so the same light falls on both. What each adds to the bare floor must be as bright
## (pixels over `BRIGHT`) and as saturated (colourful) as the old, at least `MIN_SHARE` of it.
## With `SHOP_LIT_SHOT_DIR=<dir>` set it saves a picture of each. Run:
## `SHOP_LIT_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=art/shop_items_lit_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const Old := preload("res://tests/_art/old_shop_look.gd")
const SCRATCH := "user://settings_shop_items_lit_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "garage_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
## The item's catalogue key and the pieces whose rows carry it (`PieceCarries.canonical`).
const KINDS := [
	["till", ["shop_counter"]], ["jar", ["shop_counter"]], ["pack", ["shop_counter"]],
	["pot", ["noodle_counter"]], ["bowl", ["noodle_counter"]],
	["instruments", ["tool_cart"]], ["syringe", ["tool_cart"]], ["screen", ["tool_cart"]],
	["cyber_arm", ["cyberware_shelf"]], ["cyber_eye", ["cyberware_shelf"]],
	["cyber_chip", ["cyberware_shelf"]], ["cyber_jar", ["cyberware_shelf"]],
]
const ZOOM := 4.0
## The patch of floor each item is looked at over, in px across.
const BOX := 30.0
## A pixel this much unlike the bare floor belongs to the item (its shadow too).
const CHANGED := 0.08
## A pixel at least this bright (the picture's luminance, 0 to 1).
const BRIGHT := 0.35
## A pixel at least this saturated and this bright.
const SATURATION := 0.45
const VALUE := 0.3
## An old measure under this many pixels says nothing (the pot has no bright pixel at all): the
## kind is judged by the other measures, and by its mean colour, which every kind has.
const MIN_PX := 12
## What the new item shows of the old drawing, per kind, each bar its measured result (the picture
## is the same every run: `SHOP_LIT_RECORD=<file>` writes old and new) with a little to spare for
## the GPU: `colour` the most the mean colour of what it adds may be from the old's (the largest
## channel), `cover` the least and the most share of the pixels it changes (an item of volume
## changes more: its shadow and outline ring), `middle` (when it is there) the most the pixel in
## the middle may be from the old's (a pot's broth), `bright` and `sat` the least share of the
## old's bright and saturated pixels (0: the old has under `MIN_PX` of them, so the kind is not
## judged by it, and the test says so). The cause of each kind's gap is on its row; the shared one
## is that the lit 3D picture darkens a flat colour a shade.
const BARS := {
	# a glowing pane on a dark body, flat keys; the till's body is a box with a shadow (cover 2.1)
	"till": { "colour": 0.085, "cover": Vector2(1.8, 2.4), "bright": 1.3, "sat": 0.0 },
	"jar": { "colour": 0.035, "cover": Vector2(0.9, 1.2), "bright": 1.2, "sat": 0.0 },
	# red 0.47 flat against 0.29 lit; a pack of volume covers 2.9 times the flat one
	"pack": { "colour": 0.19, "cover": Vector2(2.5, 3.2), "bright": 0.0, "sat": 1.1 },
	# the pot: a dark outline ring, two handles and a shadow the flat drawing has not (0.081 darker)
	"pot": {
		"colour": 0.09, "cover": Vector2(1.3, 1.7), "bright": 0.0, "sat": 0.0, "middle": 0.05,
	},
	# the bowl keeps its rim of its own colour to the footprint's edge, the broth inside (bright
	# 640 of 960: a shadow ring)
	"bowl": { "colour": 0.08, "cover": Vector2(0.75, 1.0), "bright": 0.6, "sat": 0.9 },
	"instruments": { "colour": 0.035, "cover": Vector2(1.7, 2.2), "bright": 0.0, "sat": 0.0 },
	"syringe": { "colour": 0.025, "cover": Vector2(1.7, 2.2), "bright": 1.9, "sat": 0.9 },
	# a screen's lit pane is a thinner line in 3D (bright .78)
	"screen": { "colour": 0.055, "cover": Vector2(1.0, 1.3), "bright": 0.7, "sat": 1.4 },
	"cyber_arm": { "colour": 0.055, "cover": Vector2(1.0, 1.3), "bright": 0.0, "sat": 1.2 },
	# an eye's bright white is a sphere with a shaded side (bright .82)
	"cyber_eye": { "colour": 0.09, "cover": Vector2(0.9, 1.2), "bright": 0.75, "sat": 0.9 },
	"cyber_chip": { "colour": 0.04, "cover": Vector2(1.2, 1.6), "bright": 0.0, "sat": 0.6 },
	# a jar of volume: its glass is darker lit than flat (0.1 under) and it casts a shadow (cover
	# 1.9)
	"cyber_jar": { "colour": 0.11, "cover": Vector2(1.6, 2.1), "bright": 0.0, "sat": 0.0 },
}

var _window: SubViewport
var _camera: Camera2D
var _mirror: MeshCarrier
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "A shop item reads as bright as the drawing it replaced (windowed)",
		"description": "A 3D match in a window, each shop and special-room item twice at one "
			+ "spot (the old painters' drawing as a flat textured sheet, the new item): the "
			+ "item's bright and saturated pixels are at least two fifths of the old drawing's. "
			+ "Windowed.",
		"tags": ["render", "3d", "windowed", "items", "unbake"],
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
	var built := await _start(t)
	if not t.require(not built.is_empty(), "a match started in 3D"):
		return
	var spot := _widest_floor()
	_camera.zoom = Vector2(ZOOM, ZOOM)
	_camera.global_position = spot
	await t.frames(60)
	var bare := await _picture(t, "bare")
	for kind: Array in KINDS:
		var key: String = kind[0]
		var row := _row(key, kind[1])
		if not t.require(not row.is_empty(), "premise: a shop piece carries a %s" % key):
			continue
		var sheet := _old(key, row, spot)
		var old := _measure(await _picture(t, key + "_old"), bare)
		sheet.queue_free()
		var item := ObjectFactory.spawn(_item(key, row), spot, _world, {})
		var new := _measure(await _picture(t, key + "_new"), bare)
		item.queue_free()
		_judge(t, key, old, new)
	await MainProbe.close(t, _window)


## Main whole in the window with a played 3D match started and the camera on it: the match built
## (`{}` when it did not start).
func _start(t: TestContext) -> Dictionary:
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
	if built.is_empty():
		return built
	_camera.set_process(false)
	_camera.set_physics_process(false)
	await t.frames(30)
	_mirror = main.get_node("View3D").carrier
	_world = built["world"]
	for body: Node in PlanProbe.bodies_under(_world):
		if MeshKinds.kind_of(body) == MeshKinds.WALL:
			for proxy in _mirror.proxies_of(body):
				proxy.visible = false
	return built


## The first carrying row for `key` among `pieces` (`PieceCarries.canonical`, a fridge's and a
## shelf's rows are made from the look): `{}` when none.
func _row(key: String, pieces: Array) -> Dictionary:
	for piece: String in pieces:
		var definition := WorldGen.object_definition(piece)
		for row: Dictionary in PieceCarries.canonical(definition, PieceHeights.spec_of(definition)):
			if row["key"] == key:
				return row
	return {}


## The item's definition as the row that carries it sets it.
func _item(key: String, row: Dictionary) -> Dictionary:
	return PieceCarries.patched(WorldGen.object_definition(key), PieceCarries.patch_of(row))


## The old drawing of `key` (in the colour its `row` gives) as a flat textured sheet on the floor
## at `spot`, as the painted top had it.
func _old(key: String, row: Dictionary, spot: Vector2) -> MeshInstance3D:
	var foot: Vector2i = Old.FEET[key]
	var colour: Color = row.get("color", WorldGen.object_definition(key)["color"])
	var c := PixelCanvas.new(foot.x, foot.y, 7, Vector2.ZERO)  # the flat paint: no light of its own
	Old.draw(c, key, colour)
	var image := Image.create(foot.x, foot.y, false, Image.FORMAT_RGBA8)
	for y in foot.y:
		for x in foot.x:
			var p := c.at(x, y)
			p.a = 1.0 if c.covered(x, y) else 0.0
			image.set_pixel(x, y, p)
	var plane := PlaneMesh.new()  # lit as the painted top was: the textured toon on a flat sheet
	plane.size = Vector2(foot) * RenderConfig.unit
	var sheet := MeshNodes.textured(
		plane, ImageTexture.create_from_image(image),
		Rect2(-foot.x * 0.5, -foot.y * 0.5, foot.x, foot.y), { "cutout": true },
	) as MeshInstance3D
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheet.position = Vector3(spot.x, MeshKitConfig.decal_lift, spot.y) * RenderConfig.unit
	_mirror.add_child(sheet)
	return sheet


## The window's picture (saved when asked to).
func _picture(t: TestContext, name_: String) -> Image:
	await t.frames(20)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("SHOP_LIT_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, name_])
	return image


## What `image` shows over `bare` in the middle box: `{ changed, bright, sat, colour }`, the
## pixel counts and the mean colour of the changed pixels.
func _measure(image: Image, bare: Image) -> Dictionary:
	var centre := Vector2i(Vector2(image.get_size()) * 0.5)
	var half := int(BOX * ZOOM * 0.5)
	var out := {
		"changed": 0, "bright": 0, "sat": 0, "colour": Color(
			0,
			0,
			0,
		), "middle": image.get_pixelv(centre),
	}
	var sum := Vector3.ZERO
	for y in range(centre.y - half, centre.y + half):
		for x in range(centre.x - half, centre.x + half):
			var p := image.get_pixel(x, y)
			var q := bare.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) < CHANGED:
				continue
			out["changed"] += 1
			out["bright"] += 1 if p.get_luminance() >= BRIGHT else 0
			out["sat"] += 1 if p.s >= SATURATION and p.v >= VALUE else 0
			sum += Vector3(p.r, p.g, p.b)
	if out["changed"] > 0:
		sum /= float(out["changed"])
		out["colour"] = Color(sum.x, sum.y, sum.z)
	return out


## The checks of one kind: every one measures something the old drawing has (an old measure under
## `MIN_PX` is not used), and the kind's own bar (`BARS`) holds.
func _judge(t: TestContext, key: String, old: Dictionary, new: Dictionary) -> void:
	var record := OS.get_environment("SHOP_LIT_RECORD")
	if record != "":
		var f := FileAccess.open(record, FileAccess.READ_WRITE) if FileAccess.file_exists(record) \
				else FileAccess.open(record, FileAccess.WRITE)
		f.seek_end()
		f.store_line("%s old %s new %s" % [key, _line(old), _line(new)])
		return
	var bar: Dictionary = BARS[key]
	t.require(
		old["changed"] >= MIN_PX,
		"%s's old prop shows over the floor (%d px)" % [key, old["changed"]],
	)
	var gap := _gap(old["colour"], new["colour"])
	t.check(
		gap <= float(bar["colour"]),
		"the new %s is the colour of its prop (%.3f apart, %s against %s)"
		% [key, gap, new["colour"], old["colour"]],
	)
	_judge_cover(t, key, old["changed"], new["changed"], bar["cover"])
	if bar.has("middle"):  # a thing with something in its middle (the pot's broth) shows it
		t.check(
			_gap(old["middle"], new["middle"]) <= float(bar["middle"]),
			"the new %s's middle is its prop's (%s against %s)"
			% [key, new["middle"], old["middle"]],
		)
	for measure: String in ["bright", "sat"]:
		if bar[measure] > 0.0:
			t.require(
				old[measure] >= MIN_PX,
				"%s: the old prop has %s px to measure" % [key, measure],
			)
			t.check(
				new[measure] >= int(old[measure] * bar[measure]),
				"the new %s keeps its prop's %s pixels (%d against %d)"
				% [key, measure, new[measure], old[measure]],
			)
		else:
			t.check(
				old[measure] < MIN_PX,
				"%s: the old prop has too few %s px to measure (%d)" % [key, measure, old[measure]],
			)


## The new item changes as many pixels as its prop, within `share`'s least and most of them.
func _judge_cover(t: TestContext, key: String, old: int, new: int, share: Vector2) -> void:
	t.check(
		new >= int(old * share.x) and new <= int(old * share.y),
		"the new %s covers what its prop does (%d px against %d: %.1f to %.1f times)"
		% [key, new, old, share.x, share.y],
	)


func _line(m: Dictionary) -> String:
	var c: Color = m["colour"]
	return "%d %d %d %.3f %.3f %.3f" % [m["changed"], m["bright"], m["sat"], c.r, c.g, c.b]


## How far apart two colours are: the largest of their channels' differences.
func _gap(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## The emptiest spot of the house's largest floor: the grid point furthest from every body, where
## nothing stands over or beside the item and the dusk lights it.
func _widest_floor() -> Vector2:
	var best := Rect2()
	for node: Node in _world.get_tree().get_nodes_in_group(&"floors"):
		if _world.is_ancestor_of(node) and node.get("art") != "street":
			var rect := Rect2((node as Node2D).global_position, node.get("size"))
			if rect.get_area() > best.get_area():
				best = rect
	var bodies: Array[Vector2] = []
	for body: Node in PlanProbe.bodies_under(_world):
		if body is Node2D and MeshKinds.kind_of(body) != MeshKinds.FLOOR:
			bodies.append((body as Node2D).global_position)
	var spot := best.get_center()
	var room := -1.0
	for y in range(int(best.position.y) + 40, int(best.end.y) - 40, 10):
		for x in range(int(best.position.x) + 40, int(best.end.x) - 40, 10):
			var near := INF
			for at in bodies:
				near = minf(near, at.distance_to(Vector2(x, y)))
			if near > room:
				room = near
				spot = Vector2(x, y)
	return spot
