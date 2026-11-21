extends GameTest
## Probe of #193's pixel post (windowed only: headless draws nothing): what the real 3D view costs a
## frame, in the downtown district `perf/match_10v10_stress` builds. The 10v10 match plays on; in
## blocks, round after round, the camera walks the same fixed route around the centre house,
## turning through a full circle as it goes, and each block's frame times are sampled with the CPU
## render times of the root viewport and the 3D view's (Godot 4.4 on Metal reports the GPU render
## time as 0, so frame time is the measure) and the slowest of the frames just after the block
## starts. The view is Main's `View3D` (the toon material, the outline pass, the internal
## resolution of `RenderConfig`, the supersample of `PixelPostConfig`) over the real `MeshCarrier`,
## the 2D world hidden (its scripts still running).
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
const LIMIT_MS := 33.4
## The least mean brightness a lit frame of the district has (measured lit 0.27, unlit 0.002).
const LIT := 0.1
## The seed the view's lights flicker by.
const LIGHT_SEED := 10

var _view: CanvasLayer
## The mean brightness (0 to 1) of each mid-route frame: a view with no light draws outlines on
## black.
var _brightness: Array[float] = []
var _camera: Camera2D
var _root_rid: RID


func describe() -> Dictionary:
	return {
		"name": "The 3D view with the pixel post, frame cost (probe)",
		"description": "The same camera route in the 10v10 district under the real 3D view with "
			+ "the pixel post, frame times at two resolutions. Windowed only.",
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


## The window and the world as the probe found them: the camera's own scripts on.
func _restore() -> void:
	_camera.set_process(true)
	_camera.set_physics_process(true)


## Every mode at every size recorded all its frames, each a finite positive time, and the view drew
## the lit district (not black).
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
			t.check(
				int(frame["count"]) == FRAMES * ROUNDS,
				"%s: %d frames recorded (%d)" % [label, int(frame["count"]), FRAMES * ROUNDS],
			)
			for key: String in ["mean", "p95", "max"]:
				var value: float = frame[key]
				t.check(
					is_finite(value) and value > 0.0,
					"%s: %s frame time is %s" % [label, key, value],
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
		samples[mode] = { "frame": [], "gpu": [], "cpu": [], "settle": [] }
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
		}
	return out


func _block(t: TestContext, mode: String, centre: Vector2, into: Dictionary) -> void:
	var last := Time.get_ticks_usec()
	for i in SETTLE:
		_route(centre, 0.0)
		await t.frames(1)
		var settled := Time.get_ticks_usec()
		into["settle"].append((settled - last) / 1000.0)
		last = settled
	for i in FRAMES:
		_route(centre, float(i) / float(FRAMES))
		await t.frames(1)
		if i == int(FRAMES * 0.5):
			_shot(t, mode)
			_brightness.append(_mean_brightness(t))
		var now := Time.get_ticks_usec()
		into["frame"].append((now - last) / 1000.0)
		last = now
		var view_rid: RID = _view.viewport.get_viewport_rid()
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_root_rid)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_root_rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(view_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(view_rid)
		into["gpu"].append(gpu)
		into["cpu"].append(cpu)


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
		out["over_33_4"] = sorted.filter(func(v: float) -> bool: return v > LIMIT_MS).size()
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
			)
	var path := OS.get_environment("POST_PROBE_OUT")
	if path != "":
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			var why := FileAccess.get_open_error()
			push_error("POST_PROBE_OUT %s cannot be written (%s)" % [path, why])
			return
		file.store_string(text)
