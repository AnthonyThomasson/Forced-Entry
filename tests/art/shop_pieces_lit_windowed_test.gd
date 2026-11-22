extends GameTest
## A shop or special-room piece reads as bright and as colourful as the piece it replaced in the
## lit 3D picture, in a real window (windowed only: the headless renderer draws nothing; #194
## unbake-c, D21 "the old look kept", `docs/stacked-items.md` SI16). A played 3D match (garage_home,
## seed 2); for each of the shop counter, noodle counter, booth, tool cart, monitor ledge, drinks
## fridge, snack machine, shelf aisle and cyberware shelf, the OLD piece
## (`tests/_art/old_shop_pieces.gd`: the mesh and painters of commit 08f43a10, the till, bowls,
## glass and stock built into it) and then the NEW one (the hollow piece and the free items it
## carries: `RoomItems.carry`) stand at the SAME spot under the same camera, one after the other, so
## the same light falls on both. What each adds to the bare floor is measured: the pixels over
## `BRIGHT`, the saturated ones, the mean luminance and the mean colour of the changed ones; the new
## piece keeps what its own `BARS` row says of the old's. With `SHOP_PIECE_SHOT_DIR=<dir>` set it
## saves a picture of each. Run:
## `SHOP_PIECE_SHOT_DIR=<dir> tools/run_tests.sh --windowed --id=art/shop_pieces_lit_windowed`.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const PlanProbe := preload("res://tests/_general/plan_probe.gd")
const CameraScript := preload("res://scenes/general/camera_controller.gd")
const Old := preload("res://tests/_art/old_shop_pieces.gd")
const SCRATCH := "user://settings_shop_pieces_lit_windowed_test.json"
const SIZE := Vector2i(1152, 648)
const SPEC := {
	"seed": 2,
	"plan": "garage_home",
	"defenders": { "count": 2 },
	"invaders": { "count": 1 },
}
const PIECES := [
	"shop_counter", "noodle_counter", "noodle_booth", "tool_cart", "monitor_wall",
	"drinks_fridge", "snack_machine", "shelf_aisle", "cyberware_shelf",
]
const ZOOM := 3.0
## The picture is measured over the piece's footprint and this much more, in px, all round, and
## this much above it (a tall piece rises up the picture).
const MARGIN := 14.0
const RISE := 70.0
## A pixel this much unlike the bare floor belongs to the piece (its shadow too).
const CHANGED := 0.08
## A pixel at least this bright (the picture's luminance, 0 to 1).
const BRIGHT := 0.35
## A pixel at least this saturated and this bright.
const SATURATION := 0.45
const VALUE := 0.3
## An old measure under this many pixels says nothing: the piece is judged by the others.
const MIN_PX := 12
## The shape of a stocked front (a fridge's, a snack machine's): over the picture rows of the
## front face (this many art px above the footprint's front edge, to this many), the most separate
## runs of stock-coloured pixels one scan line crosses (a bottle, a pack: a run at least this many
## picture px wide, its luminance this much under the brightest of the band's) the piece shows.
const FRONT_ROWS := Vector2(12.0, 3.0)
const RUN_WIDTH := 4
const RUN_DEPTH := 0.25
## What the new piece keeps of the old one, per piece: `bright` and `sat` the least share of the
## old's bright and saturated pixels, `lum` the most its mean luminance may be under the old's,
## `colour` the most its mean colour may be from the old's (the largest channel), and on a fridge
## and a snack machine `runs` (`_front_runs`) the stock a scan line of its front shows. Each bar is
## what the piece measures in a window (the picture is the same every run:
## `SHOP_PIECE_RECORD=<file>` writes old and new) with a little under it for the GPU; a bar that
## sits at its result has a cause: the booth's bowls are painted the old size but are a cylinder
## with a dark ring and a shadow the flat drawing had not (bright .64); the cart's chrome tools
## lying on a tray are thinner, less saturated bars than the flat line (sat .53); the fridge's lit
## front has a window cut for each bottle, so the bottles show dark against it, not the pane the old
## drew over them (lum .023
## under, blue .033 under); the snack machine's pane is dim and its packs stand behind its windows
## (lum .017 under); the aisle's boards and packs are real and lit from the side (sat .89, colour
## .025); the cyberware shelf holds 26 of the old 38 items (bright .87).
const BARS := {
	"shop_counter": { "bright": 1.3, "sat": 0.9, "lum": 0.005, "colour": 0.015 },
	"noodle_counter": { "bright": 1.0, "sat": 0.95, "lum": 0.005, "colour": 0.015 },
	"noodle_booth": { "bright": 0.6, "sat": 0.95, "lum": 0.005, "colour": 0.01 },
	"tool_cart": { "bright": 1.0, "sat": 0.5, "lum": 0.005, "colour": 0.01 },
	"monitor_wall": { "bright": 0.95, "sat": 0.95, "lum": 0.005, "colour": 0.005 },
	"drinks_fridge": {
		"bright": 0.95, "sat": 1.3, "lum": 0.03, "colour": 0.04,
		"runs": { "share": 0.75, "floor": 6 },
	},
	"snack_machine": {
		"bright": 1.0, "sat": 0.95, "lum": 0.02, "colour": 0.025,
		"runs": { "share": 0.0, "floor": 4 },
	},
	"shelf_aisle": { "bright": 1.9, "sat": 0.85, "lum": 0.02, "colour": 0.03 },
	"cyberware_shelf": { "bright": 0.85, "sat": 1.3, "lum": 0.005, "colour": 0.015 },
}

var _window: SubViewport
var _camera: Camera2D
var _mirror: MeshCarrier
var _world: Node


func describe() -> Dictionary:
	return {
		"name": "A shop piece reads as bright as the piece it replaced (windowed)",
		"description": "A 3D match in a window, each shop and special-room piece twice at one "
			+ "spot (the old mesh and painters of 08f43a10, the new hollow piece with its free "
			+ "items): its bright and saturated pixels, its mean luminance and colour keep the "
			+ "old piece's, to a bar each piece has. Windowed.",
		"tags": ["render", "3d", "windowed", "items", "unbake"],
		"timeout": 300.0,
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
	for key: String in PIECES:
		var definition := WorldGen.object_definition(key)
		var old_piece := ObjectFactory.spawn(definition, spot, _world, {})
		await t.frames(5)
		for proxy in _mirror.proxies_of(old_piece):
			proxy.visible = false
		var rig := Old.rig(old_piece)
		rig.position = Vector3(spot.x, 0.0, spot.y) * RenderConfig.unit
		_mirror.add_child(rig)
		var old := _measure(await _picture(t, key + "_old"), bare, definition["size"])
		rig.queue_free()
		old_piece.queue_free()
		await t.frames(5)
		var piece := ObjectFactory.spawn(definition, spot, _world, {})
		var carried := RoomItems.carry(piece, definition, _world, "gallery")
		var new := _measure(await _picture(t, key + "_new"), bare, definition["size"])
		piece.queue_free()
		for row: Dictionary in carried:  # its items stand in the world, not under it
			(row["node"] as Node).queue_free()
		await t.frames(5)
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


## The window's picture (saved when asked to).
func _picture(t: TestContext, name_: String) -> Image:
	await t.frames(20)
	RenderingServer.force_draw(false)  # on demand: a covered window never draws
	var image := _window.get_texture().get_image()
	var dir := OS.get_environment("SHOP_PIECE_SHOT_DIR")
	if dir != "":
		image.save_png("%s/%s.png" % [dir, name_])
	return image


## What `image` shows over `bare` around a piece of footprint `size` at the picture's middle:
## `{ changed, bright, sat, lum, colour }`, the pixel counts, the mean luminance and the mean colour
## of the changed pixels.
func _measure(image: Image, bare: Image, size: Vector2) -> Dictionary:
	var centre := Vector2(image.get_size()) * 0.5
	var half := (size * 0.5 + Vector2(MARGIN, MARGIN)) * ZOOM
	var area := Rect2i(
		centre - half - Vector2(0.0, RISE * ZOOM),
		half * 2.0 + Vector2(0.0, RISE * ZOOM),
	).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var out := {
		"changed": 0, "bright": 0, "sat": 0, "lum": 0.0, "colour": Color(0, 0, 0),
		"runs": _front_runs(image, size),
	}
	var sum := Vector3.ZERO
	var light := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := image.get_pixel(x, y)
			var q := bare.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) < CHANGED:
				continue
			out["changed"] += 1
			out["bright"] += 1 if p.get_luminance() >= BRIGHT else 0
			out["sat"] += 1 if p.s >= SATURATION and p.v >= VALUE else 0
			light += p.get_luminance()
			sum += Vector3(p.r, p.g, p.b)
	if out["changed"] > 0:
		sum /= float(out["changed"])
		out["colour"] = Color(sum.x, sum.y, sum.z)
		out["lum"] = light / float(out["changed"])
	return out


## The checks of one piece: every measure the old piece has (an old count under `MIN_PX` is not
## used, and the test says so) and the piece's own bar (`BARS`) holds.
func _judge(t: TestContext, key: String, old: Dictionary, new: Dictionary) -> void:
	var record := OS.get_environment("SHOP_PIECE_RECORD")
	if record != "":
		var f := FileAccess.open(record, FileAccess.READ_WRITE) if FileAccess.file_exists(record) \
				else FileAccess.open(record, FileAccess.WRITE)
		f.seek_end()
		f.store_line("%s old %s new %s" % [key, _line(old), _line(new)])
		return
	var bar: Dictionary = BARS[key]
	t.require(old["changed"] >= MIN_PX, "%s's old piece shows over the floor" % key)
	for measure: String in ["bright", "sat"]:
		if bar[measure] > 0.0:
			t.require(
				old[measure] >= MIN_PX,
				"%s: the old piece has %s px to measure (%d)" % [key, measure, old[measure]],
			)
			t.check(
				new[measure] >= int(old[measure] * bar[measure]),
				"the new %s keeps its %s pixels (%d against %d, at least %.0f%%)"
				% [key, measure, new[measure], old[measure], bar[measure] * 100.0],
			)
		else:
			t.check(
				old[measure] < MIN_PX,
				"%s: the old piece has too few %s px to measure (%d)" % [
					key,
					measure,
					old[measure],
				],
			)
	t.check(
		new["lum"] >= old["lum"] - float(bar["lum"]),
		"the new %s is as light on average (%.3f against %.3f, %.3f under at most)"
		% [key, new["lum"], old["lum"], bar["lum"]],
	)
	if bar.has("runs"):
		_judge_runs(t, key, old["runs"], new["runs"], bar["runs"])
	var gap := _gap(old["colour"], new["colour"])
	t.check(
		gap <= float(bar["colour"]),
		"the new %s is the colour of the old (%.3f apart at most %.3f: %s against %s)"
		% [key, gap, bar["colour"], new["colour"], old["colour"]],
	)


## The new piece shows its stock through the glass: as many runs of it on a scan line as the old
## front did, to `share` of them.
func _judge_runs(t: TestContext, key: String, old: int, new: int, bar: Dictionary) -> void:
	var least := maxi(int(bar["floor"]), int(old * float(bar["share"])))
	t.check(
		new >= least,
		"the new %s shows its stock through the glass (%d runs on a scan line against %d, at least "
		% [key, new, old] + "%.0f%%, none under %d)" % [float(bar["share"]) * 100.0, bar["floor"]],
	)


## The most runs of stock a scan line of the front face of a piece of footprint `size` crosses
## (`FRONT_ROWS`): the pixels well under the band's brightest are the stock, a run of them at
## least `RUN_WIDTH` px wide one item (a lit front with nothing standing in it has none).
func _front_runs(image: Image, size: Vector2) -> int:
	var centre := Vector2(image.get_size()) * 0.5
	var front := centre.y + size.y * 0.5 * ZOOM
	var cols := Vector2i(
		int(centre.x - (size.x * 0.5 - 6.0) * ZOOM), int(centre.x + (size.x * 0.5 - 6.0) * ZOOM)
	)
	var rows := Vector2i(int(front - FRONT_ROWS.x * ZOOM), int(front - FRONT_ROWS.y * ZOOM))
	var brightest := 0.0
	for y in range(rows.x, rows.y):
		for x in range(cols.x, cols.y):
			brightest = maxf(brightest, image.get_pixel(x, y).get_luminance())
	var most := 0
	for y in range(rows.x, rows.y):
		var runs := 0
		var width := 0
		for x in range(cols.x, cols.y + 1):
			if x < cols.y and image.get_pixel(x, y).get_luminance() < brightest - RUN_DEPTH:
				width += 1
				continue
			runs += 1 if width >= RUN_WIDTH else 0
			width = 0
		most = maxi(most, runs)
	return most


func _line(m: Dictionary) -> String:
	var c: Color = m["colour"]
	return "%d %d %d %.3f %.3f %.3f %.3f runs %d" % [
		m["changed"],
		m["bright"],
		m["sat"],
		m["lum"],
		c.r,
		c.g,
		c.b,
		m["runs"],
	]


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
