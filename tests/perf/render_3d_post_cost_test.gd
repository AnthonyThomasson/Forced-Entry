extends GameTest
## Frame-time budget of the 3D view with the pixel post (windowed only: headless draws nothing):
## what a frame of the match costs with it, in the downtown district `perf/match_10v10_stress`
## builds. The 10v10 match plays on; in blocks, round after round, the camera walks the same fixed
## route around the centre house, turning through a full circle as it goes, and each block's frame
## times are sampled with the CPU render times of the root viewport and the 3D view's (Godot 4.4 on
## Metal reports the GPU render time as 0, so frame time is the measure) and the slowest of the
## frames just after the block starts. The view is Main's `View3D` (the toon material, the outline
## pass, the internal resolution of `RenderConfig`, the supersample of `PixelPostConfig`) over the
## real `MeshCarrier`, the 2D world hidden (its scripts still running).
## At both window sizes the frames must meet the match standard (`Perf.SMOOTH_*`: 16.7 ms avg, 20
## p95, 33.4 max). The probe's own mid-route screen readback (and the PNG it saves) runs between
## two samples, in none of them.
## Every sampled frame must have been drawn: a window the desktop does not show (fully covered or
## minimized) gets nothing on screen, and such a frame costs next to nothing. At every sample two
## things are read: the engine's drawn-frame count, which must have moved, and whether the main
## window can draw (`DisplayServer.window_can_draw`, its occlusion flag), which must be so now and
## at the sample before. Both are needed: the engine also counts a draw that only frees GPU
## resources and puts nothing on screen. A frame that fails either fails the test; no sample is
## dropped. The window is kept above the others while the probe runs (where it sits among them;
## what a frame draws is the same). The probe needs `--fixed-fps` (tools/run_tests.sh): paced to
## the clock (the in-game runner), two samples can share one drawn frame, and it fails.
## Run: `tools/run_tests.sh --windowed --quiet --id=perf/render_3d_post_cost` (add `--verbose`);
## the numbers print as `POST` lines and, with `POST_PROBE_OUT=<file>` set, as JSON;
## `POST_PROBE_SHOTS=<dir>` saves each mode's mid-route frame.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const ViewScript := preload("res://scenes/main_view3d.gd")
const SIZES: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(2560, 1440)]
const MODES: Array[String] = ["3D post"]
const FRAMES := 240
const ROUNDS := 3
const SETTLE := 20
const ROUTE_RADIUS := 520.0
## The least mean brightness a lit frame of the district has (measured lit 0.27, unlit 0.002).
const LIT := 0.1
## The seed the view's lights flicker by.
const LIGHT_SEED := 10

## What the probe reads of the engine and the window; variables so the self-test
## `_harness/render_3d_post_undrawn` can put its own here.
## The engine's count of drawn frames: one more for each main-loop iteration (one a sample, under
## `--fixed-fps`) that drew, whether or not the frame reached the screen.
var frames_drawn: Callable = Engine.get_frames_drawn
## Whether the main window can draw: false while the desktop shows none of it, and headless.
var can_draw: Callable = DisplayServer.window_can_draw
## The main window's always-on-top flag, read and set.
var on_top: Callable = DisplayServer.window_get_flag.bind(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP)
var set_on_top: Callable = func(on: bool) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, on)
## The drawn-frame count at the last sample, and whether the window could draw then.
var _drawn_at := 0
var _could_draw := false
var _view: CanvasLayer
## The mean brightness (0 to 1) of each mid-route frame: a view with no light draws outlines on
## black.
var _brightness: Array[float] = []
var _camera: Camera2D
var _root_rid: RID


func describe() -> Dictionary:
	return {
		"name": "The 3D view with the pixel post, frame cost",
		"description": "The same camera route in the 10v10 district under the real 3D view with "
			+ "the pixel post: frame times at two resolutions within the match standard. "
			+ "Windowed only.",
		"tags": ["perf", "render", "3d", "pixel"],
		"timeout": 900.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	Perf.configure_match(s, 10)
	s.lock_interaction([&"camera"])


func run(t: TestContext) -> void:
	if DisplayServer.get_name() == "headless":
		t.skip("windowed only: headless draws nothing (tools/run_tests.sh --windowed)")
		return
	_keep_on_top(t)
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(characters.size() == 20, "twenty combatants spawned"):
		return
	if not await Perf.warm_until_contact(t, "iso render cost", characters):
		return
	var centre := Vector2.ZERO
	for c: Node2D in characters:
		centre += c.global_position
	centre /= float(characters.size())
	_set_up(t)
	var results := {}
	var original := DisplayServer.window_get_size()
	for size in SIZES:
		DisplayServer.window_set_size(size)
		await t.frames(10)
		var actual := t.world.get_tree().root.get_visible_rect().size
		t.require(Vector2i(actual) == size, "the window is %s (is %s)" % [size, actual])
		results[str(size)] = await _rounds(t, centre)
	DisplayServer.window_set_size(original)
	_restore()
	_report(results)
	_check(t, results)


## Keep the window above the others, so none covers it, until the test ends or its world leaves
## the tree (the runner's Esc / Back ends it with no verdict).
func _keep_on_top(t: TestContext) -> void:
	var put := set_on_top
	var was: bool = on_top.call()
	put.call(true)
	var put_back := func() -> void: put.call(was)
	t.finished.connect(put_back, CONNECT_ONE_SHOT)
	t.world.tree_exiting.connect(put_back, CONNECT_ONE_SHOT)


## Note frames from here.
func start_noting() -> void:
	_drawn_at = frames_drawn.call()
	_could_draw = can_draw.call()


## Note into `noted` the frame since the last sample: sampled, and undrawn if the count stood still
## or the window could not draw at either end of it.
func note_drawn(noted: Dictionary) -> void:
	var now: int = frames_drawn.call()
	var can: bool = can_draw.call()
	noted["sampled"] += 1
	if now == _drawn_at or not (can and _could_draw):
		noted["undrawn"] += 1
	_drawn_at = now
	_could_draw = can


## The window and the world as the probe found them: the camera's own scripts on.
func _restore() -> void:
	_camera.set_process(true)
	_camera.set_physics_process(true)


## Every mode at every size drew every sampled frame, recorded all its frames and met the standard,
## and the view drew the lit district (not black).
func _check(t: TestContext, results: Dictionary) -> void:
	t.check(not _brightness.is_empty(), "a mid-route frame was read")
	for light: float in _brightness:
		t.check(
			light >= LIT,
			"the view draws the lit district, not black (mean brightness %.3f)" % light,
		)
	for size: String in results:
		for mode: String in results[size]:
			var frame: Dictionary = results[size][mode]["frame"]
			var label := "%s %s" % [size, mode]
			_check_drawn(t, label, results[size][mode]["drawn"])
			t.check(
				int(frame["count"]) == FRAMES * ROUNDS,
				"%s: %d frames recorded (%d)" % [label, int(frame["count"]), FRAMES * ROUNDS],
			)
			Perf.within_frames(
				t,
				label,
				{ "avg_ms": frame["mean"], "p95_ms": frame["p95"], "max_ms": frame["max"] },
			)


## Each settle and measured frame was looked at and was drawn.
func _check_drawn(t: TestContext, label: String, noted: Dictionary) -> void:
	var sampled := int(noted["sampled"])
	var undrawn := int(noted["undrawn"])
	var expected := ROUNDS * (SETTLE + FRAMES)
	t.check(
		undrawn == 0 and sampled == expected,
		(
			"%s: every sampled frame was drawn (%d of %d sampled frames not drawn, %d expected). "
			+ "An undrawn frame costs next to nothing, so these times cannot be judged: keep the "
			+ "window visible (not covered, occluded or minimized) and run it with --fixed-fps "
			+ "(tools/run_tests.sh; the in-game runner has none)"
		) % [label, undrawn, sampled, expected],
	)


func _set_up(t: TestContext) -> void:
	_camera = t.world.get_viewport().get_camera_2d()
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.zoom = Vector2.ONE
	_view = ViewScript.new()
	t.world.add_child(_view)
	_view.begin(_camera)
	_view.mirror_world(t.world)
	# lit as Main lights it: without lights every surface draws black
	_view.light_world(t.world, LIGHT_SEED, WorldGen.district_rooms(t.world.district))
	t.world.visible = false
	_root_rid = t.world.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_root_rid, true)
	RenderingServer.viewport_set_measure_render_time(_view.viewport.get_viewport_rid(), true)


func _rounds(t: TestContext, centre: Vector2) -> Dictionary:
	var samples := {}
	for mode in MODES:
		samples[mode] = {
			"frame": [],
			"gpu": [],
			"cpu": [],
			"settle": [],
			"drawn": { "sampled": 0, "undrawn": 0 },
		}
	for pass_index in ROUNDS:
		for mode: String in MODES:
			await _block(t, mode, centre, samples[mode])
	var out := {}
	for mode in MODES:
		out[mode] = {
			"frame": _stats(samples[mode]["frame"], true),
			"gpu": _stats(samples[mode]["gpu"], false),
			"cpu_render": _stats(samples[mode]["cpu"], false),
			"settle_max_ms": _stats(samples[mode]["settle"], false)["max"],
			"drawn": samples[mode]["drawn"],
		}
	return out


func _block(t: TestContext, mode: String, centre: Vector2, into: Dictionary) -> void:
	var last := Time.get_ticks_usec()
	start_noting()
	for i in SETTLE:
		_route(centre, 0.0)
		await t.frames(1)
		note_drawn(into["drawn"])
		var settled := Time.get_ticks_usec()
		into["settle"].append((settled - last) / 1000.0)
		last = settled
	for i in FRAMES:
		_route(centre, float(i) / float(FRAMES))
		await t.frames(1)
		note_drawn(into["drawn"])
		var now := Time.get_ticks_usec()
		into["frame"].append((now - last) / 1000.0)
		last = now
		var render := _render_ms()
		into["gpu"].append(render.x)
		into["cpu"].append(render.y)
		if i == int(FRAMES * 0.5):
			_shot(t, mode)
			_brightness.append(_mean_brightness(t))
			last = Time.get_ticks_usec()  # the readback and the PNG are the probe's, no frame's


## The render times of the last frame, the root viewport's and the 3D view's: GPU, CPU.
func _render_ms() -> Vector2:
	var view_rid: RID = _view.viewport.get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_root_rid)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_root_rid)
	gpu += RenderingServer.viewport_get_measured_render_time_gpu(view_rid)
	cpu += RenderingServer.viewport_get_measured_render_time_cpu(view_rid)
	return Vector2(gpu, cpu)


## The mean brightness (0 to 1) of the root viewport's frame, sampled on a 48 x 32 grid.
func _mean_brightness(t: TestContext) -> float:
	var image := t.world.get_viewport().get_texture().get_image()
	image.resize(48, 32, Image.INTERPOLATE_NEAREST)
	var total := 0.0
	for y in 32:
		for x in 48:
			total += image.get_pixel(x, y).get_luminance()
	return total / float(48 * 32)


## With `POST_PROBE_SHOTS=<dir>` set, save the mid-route frame of each mode at each window size
## (the first block of each only: a later one overwrites it).
func _shot(t: TestContext, mode: String) -> void:
	var dir := OS.get_environment("POST_PROBE_SHOTS")
	if dir == "":
		return
	var image := t.world.get_viewport().get_texture().get_image()
	var file := "%s/district_%dx%d_%s.png" % [
		dir,
		image.get_width(),
		image.get_height(),
		mode.replace(" ", "_"),
	]
	if not FileAccess.file_exists(file):
		image.save_png(file)


## The route: a circle round the centre, a full turn of the camera over it, `s` in 0..1.
func _route(centre: Vector2, s: float) -> void:
	var point := centre + Vector2.from_angle(TAU * s) * ROUTE_RADIUS
	_camera.global_position = point
	_view.rig.yaw = 45.0 + 360.0 * s


func _stats(values: Array, over_limit: bool) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	var out := {
		"count": sorted.size(),
		"mean": total / float(sorted.size()),
		"p95": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))],
		"max": sorted[sorted.size() - 1],
	}
	if over_limit:
		out["over_33_4"] = sorted.filter(
			func(v: float) -> bool: return v > Perf.SMOOTH_MAX_MS
		).size()
	return out


func _report(results: Dictionary) -> void:
	var info := {
		"machine": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"meshes": _view.carrier.count,
		"moving_meshes": _view.carrier.followed,
		"texel_match": RenderConfig.texel_match,
		"supersample": PixelPostConfig.supersample,
		"frames_per_block": FRAMES,
		"rounds": ROUNDS,
	}
	var text := JSON.stringify({ "info": info, "results": results }, "  ")
	print("POST ", info)
	for size: String in results:
		for mode: String in results[size]:
			var row: Dictionary = results[size][mode]
			print(
				"POST ",
				size,
				" ",
				mode,
				" frame ",
				row["frame"],
				" cpu_render ",
				row["cpu_render"],
				" settle_max ",
				row["settle_max_ms"],
				" drawn ",
				row["drawn"],
			)
	var path := OS.get_environment("POST_PROBE_OUT")
	if path != "":
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			var why := FileAccess.get_open_error()
			push_error("POST_PROBE_OUT %s cannot be written (%s)" % [path, why])
			return
		file.store_string(text)
