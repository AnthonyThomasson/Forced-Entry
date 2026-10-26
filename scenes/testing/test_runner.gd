extends Node2D
## Testing domain: plays game tests in the game — a second composition root beside main.gd. Two
## modes:
##   interactive — plays the test the browser picked (`Engine` meta `test_selection`, or the first
##                 match of `-- --play <filter>`), shows the result banner and keeps the world
##                 running; Rerun rebuilds it, Back/Escape returns to the browser;
##   queued      — the browser's "Run N checked" (`Engine` meta `test_queue`, ordered paths), or
##                 `-- --queue=<id,id,…>` (tools/play_tests.sh: those ids in the order given,
##                 harness tests allowed, an unknown id printed and skipped, none valid -> the
##                 browser): interactive, but plays each test in turn, pausing on its verdict then
##                 freeing it and starting the next, and prints each verdict and a final
##                 `Queue done: <summary>` line; Back/Escape cancels the rest. play_tests.sh starts
##                 it with `--log-file <dir>/godot.log` and `--out=<dir>`, so it owns its log
##                 (start-up errors count) and writes its bundles in <dir>.
## Batch runs are gdUnit's (tools/run_tests.sh, through game_test_suite.gd); the browser's Run all
## spawns one. Each test is played by a TestSession child (test_session.gd), which gives it a fresh
## TestWorld, freed between tests; the Von launcher it makes when a test needs one stays under this
## runner, so a server it started isn't killed between tests. Every engine error/warning logged
## while a test is open fails it (log_watch.gd).

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const TestSessionScript = preload("res://scenes/testing/test_session.gd")
const LogWatch = preload("res://scenes/testing/log_watch.gd")
const RESULT_HUD = preload("res://scenes/ui/testing/test_result_hud.gd")
const OVERLAY_TOGGLES = preload("res://scenes/ui/overlays/overlay_toggles.gd")
const OVERLAY_REGISTRY = preload("res://scenes/ui/overlays/overlay_registry.gd")
const PERFORMANCE_OVERLAY = preload("res://scenes/ui/overlays/performance_overlay.gd")
const BROWSER_SCENE := "res://scenes/testing/test_browser.tscn"
## Failed/timed-out tests (and GAP ones) write their event log, final state and traces here (one
## JSON per test id), unless `--out=<dir>` moves them to <dir>/failures.
const BUNDLE_DIR := "user://test_failures"
## Seconds a queued run holds each verdict before the next test starts (the HUD's Next skips it).
const QUEUE_PAUSE := 2.0
## Engine meta set once `--queue` has been queued, so a later visit to the runner (from the browser)
## plays what the browser picked instead of the command line's queue again.
const META_CLI_QUEUED := "test_cli_queued"

## The engine log tail whose errors and warnings fail the open test.
var _watch := LogWatch.new()
## Plays the open test (its entry, context and world).
var _session: Node = null
## The result banner and the overlay toggle bar.
var _hud: CanvasLayer = null
var _toggles: CanvasLayer = null
## The performance overlay (the toggle bar's Performance flag).
var _perf: CanvasLayer = null
## Whether the open test has a human-driven player (Space is then its INTERACT, not pause).
var _has_player := false
## The open test's locked interactions (`TestSetup.lock_interaction`).
var _locked: Array = []
## A queued run is going (false once it was cancelled, so a loop parked on a wait stops).
var _queue_active := false

## The camera that frames each test's actors.
@onready var _camera: Camera2D = $MainCamera


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# A run given `--out=<dir>` was also started with `--log-file <dir>/godot.log` (the engine
	# consumes that flag, so it is not visible here and does not update the project setting): follow
	# the moved log.
	var out := _option(args, "--out", "")
	if out != "":
		_watch.path_override = out.path_join("godot.log")
	var cli_queue := _option(args, "--queue", "") != "" and not Engine.has_meta(META_CLI_QUEUED)
	# The command line's queue on the runner's first visit owns a fresh log: startup errors count
	# too.
	_watch.begin(out != "" and cli_queue)
	_start_session(out)
	if args.has("--play"):
		_select_from_cli(args)
	if cli_queue:
		Engine.set_meta(META_CLI_QUEUED, true)
		_queue_from_cli(TestCatalog.csv(_option(args, "--queue", "")))
	if Engine.has_meta(TestCatalog.META_QUEUE) or Engine.has_meta(TestCatalog.META_SELECTION):
		_hud = RESULT_HUD.new()
		_hud.name = "TestResultHUD"
		add_child(_hud)
		_hud.rerun_requested.connect(_on_rerun)
		_hud.back_requested.connect(_back_to_browser)
		_hud.pause_requested.connect(func(): _set_paused(not get_tree().paused))
		# The runner keeps processing while paused (Esc / Space still work); each test's world is
		# made pausable by the session, and the test clock stops with the tree.
		process_mode = Node.PROCESS_MODE_ALWAYS
		if Engine.has_meta(TestCatalog.META_QUEUE):
			var paths: Array = Engine.get_meta(TestCatalog.META_QUEUE)
			# consumed: a later visit to the runner plays a single test
			Engine.remove_meta(TestCatalog.META_QUEUE)
			_queue_active = true
			_run_queue.call_deferred(paths)
		else:
			_run_interactive.call_deferred(String(Engine.get_meta(TestCatalog.META_SELECTION)))
	else:
		get_tree().change_scene_to_file.call_deferred(BROWSER_SCENE)


func _exit_tree() -> void:
	get_tree().paused = false


## While a test locks the camera, drop the user's own camera events (wheel, trackpad, camera keys)
## before any camera sees them; the ones the test injects itself carry `TestContext.INJECTED_META`
## and pass.
func _input(event: InputEvent) -> void:
	if (_locked.has(&"camera")
			and not event.has_meta(TestContext.INJECTED_META)
			and _is_camera_event(event)):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(Keybinds.MENU):
		_back_to_browser()
	elif event.is_action_pressed(Keybinds.PAUSE) and not _has_player and not _locked.has(&"pause"):
		_set_paused(not get_tree().paused)


## The test session every test is played through (its bundles under `out`'s `failures/` when the
## run was given one), wired to the banner and the verdict lines.
func _start_session(out: String) -> void:
	_session = TestSessionScript.new()
	_session.name = "TestSession"
	_session.watch = _watch
	_session.von.launcher_parent = self
	_session.bundle_dir = out.path_join("failures") if out != "" else BUNDLE_DIR
	add_child(_session)
	_session.status.connect(func(text: String):
		if _hud != null:
			_hud.show_status(text))
	_session.configured.connect(_on_configured)
	_session.world_built.connect(_on_world_built)
	_session.verdict_changed.connect(func(flipped: Dictionary):
		_print_result(flipped)
		if _hud != null:
			_hud.show_result(flipped))


## Whether `event` moves a camera: a trackpad gesture, the wheel's zoom or a camera key.
func _is_camera_event(event: InputEvent) -> bool:
	return (event is InputEventPanGesture
			or event.is_action(Keybinds.ZOOM_IN)
			or event.is_action(Keybinds.ZOOM_OUT)
			or event.is_action(Keybinds.CAMERA_LEFT)
			or event.is_action(Keybinds.CAMERA_RIGHT)
			or event.is_action(Keybinds.CAMERA_UP)
			or event.is_action(Keybinds.CAMERA_DOWN))


## Freeze or resume the open test's world (the banner, overlay bar and this runner keep running).
func _set_paused(on: bool) -> void:
	get_tree().paused = on
	if _hud != null:
		_hud.set_paused(on)


# --- Running one test -----------------------------------------------------------------------


## Build and run the test `entry`, leaving its world open. Returns once it has ended.
func _start(entry: Dictionary) -> void:
	_set_paused(false)
	_locked = []
	_has_player = false
	if _hud != null:
		_hud.set_pause_enabled(true)
	await _session.start(entry)


## The test's setup is known: what it locks, and whether a human-driven player walks on WASD.
func _on_configured(setup: TestSetup) -> void:
	_locked = setup.locked
	_has_player = setup.actors.any(func(a): return a["kind"] == &"player")
	if _hud != null:
		_hud.set_pause_enabled(not _locked.has(&"pause"))


## The test's world is up: frame it and give it the overlay bar.
func _on_world_built(_setup: TestSetup) -> void:
	_frame_camera()
	if not _locked.has(&"overlays"):
		_build_toggles()


## Tear the open test down (see TestSession.close) and drop its overlay bar. Returns its verdict
## record.
func _close() -> Dictionary:
	if is_instance_valid(_toggles):
		_toggles.queue_free()
	_toggles = null
	if is_instance_valid(_perf):
		_perf.queue_free()
	_perf = null
	return await _session.close()


## Frame the setup's camera targets (see TestSession.camera_targets).
## A world with a human-driven player keeps WASD for walking, so the camera's hand-pan is off there.
func _frame_camera() -> void:
	_camera.set("pan_enabled", not _has_player and not _locked.has(&"camera"))
	_camera.frame(_session.camera_targets())


# --- Interactive ----------------------------------------------------------------------------


## `--play <filter>`: pick the first test matching the words after it.
func _select_from_cli(args: PackedStringArray) -> void:
	var words := PackedStringArray()
	for a in args.slice(args.find("--play") + 1):
		if a.begins_with("--"):
			break
		words.append(a)
	var filter := " ".join(words)
	TestCatalog.show_internal = true  # a named test is played even when it is a harness self-test
	var found := TestCatalog.discover() + TestCatalog.discover_sandboxes()
	TestCatalog.show_internal = false
	for e in found:
		if TestCatalog.matches(e, filter):
			Engine.set_meta(TestCatalog.META_SELECTION, e["path"])
			return
	print("No test matches '%s'" % filter)


## `--queue=<id,id,…>`: queue those exact ids in the order given; an id that names no test is
## printed and skipped.
func _queue_from_cli(ids: Array) -> void:
	TestCatalog.show_internal = true  # a named test is played even when it is a harness self-test
	var paths := {}
	for e in TestCatalog.discover(TestCatalog.ROOT, [], ids):
		paths[e["id"]] = e["path"]
	TestCatalog.show_internal = false
	var queue: Array = []
	for id in ids:
		if paths.has(id):
			queue.append(paths[id])
		else:
			print("No test with id '%s' (skipped)" % id)
	if not queue.is_empty():
		Engine.set_meta(TestCatalog.META_QUEUE, queue)


## Play the test at `path` with the result banner, leaving its world running afterwards.
func _run_interactive(path: String) -> void:
	var entry := TestCatalog.describe(path)
	_hud.show_running(entry)
	_warn_if_unwatched()
	await _start(entry)
	var result: Dictionary = _session.result()
	_remember(result)
	_print_result(result)
	_hud.show_result(result)


## Say so on the banner (and the console) when the engine log cannot be read: errors and warnings
## would then not fail the test, which must never pass silently.
func _warn_if_unwatched() -> void:
	if not _watch.available():
		var text := "NOTE: engine log not found - errors and warnings will NOT fail this test"
		print(text)
		if _hud != null:
			_hud.show_status(text)


## Play `paths` one after another: each runs to its verdict, which is held for QUEUE_PAUSE (or until
## Next), then its world is freed and the next starts. A failure does not stop the queue; the last
## test's world stays up under a summary.
func _run_queue(paths: Array) -> void:
	var counts := {}
	for i in paths.size():
		var entry := TestCatalog.describe(paths[i])
		_hud.show_queue(i + 1, paths.size())
		_hud.show_running(entry)
		_warn_if_unwatched()
		await _start(entry)
		if not _queue_active:
			return
		var result: Dictionary = _session.result()
		_remember(result)
		_print_result(result)
		counts[result["status"]] = counts.get(result["status"], 0) + 1
		_hud.show_result(result)
		if i < paths.size() - 1:
			_hud.set_next_ready(true)
			await _queue_pause()
			if not _queue_active:
				return
			await _close()
	var summary := "%d passed, %d failed, %d timed out, %d skipped, %d gap" % [
		counts.get("PASS", 0), counts.get("FAIL", 0), counts.get("TIMEOUT", 0),
		counts.get("SKIPPED", 0), counts.get("GAP", 0),
	]
	var strays: Array = _session.stray_logs
	if not strays.is_empty():
		print("Logged outside any test (%d):" % strays.size())
		for e in strays:
			print("        ✗ %s: %s %s" % [e["severity"], e["message"], e["location"]])
		summary += ", %d logged outside any test" % strays.size()
	print("Queue done: " + summary)
	_hud.show_queue_done(summary)


## Hold the shown verdict for QUEUE_PAUSE seconds of wall time, or until the HUD's Next is pressed.
func _queue_pause() -> void:
	# not always-on: pausing holds the verdict
	var timer := get_tree().create_timer(QUEUE_PAUSE, false)
	var skip := func(): timer.time_left = 0.0
	_hud.next_requested.connect(skip, CONNECT_ONE_SHOT)
	await timer.timeout
	if is_instance_valid(_hud) and _hud.next_requested.is_connected(skip):
		_hud.next_requested.disconnect(skip)


## Rerun: tear the world down and play the same test again.
func _on_rerun() -> void:
	var path: String = _session.entry.get("path", "")
	await _close()
	_run_interactive(path)


## Back / Escape: restore statics and return to the browser (the scene change frees the world).
func _back_to_browser() -> void:
	_queue_active = false  # cancels the rest of a queued run
	get_tree().paused = false
	_session.restore()
	get_tree().change_scene_to_file(BROWSER_SCENE)


## In-game overlay toggle bar (UI) for the actors' debug overlays, as in a match.
func _build_toggles() -> void:
	var world: Node2D = _session.world
	_toggles = OVERLAY_TOGGLES.new()
	_toggles.name = "OverlayToggles"
	add_child(_toggles)
	_toggles.setup(world.overlay_flags())
	# The performance panel is the runner's own (it needs no world); the rest go to the world.
	_perf = PERFORMANCE_OVERLAY.new()
	_perf.name = "PerformanceOverlay"
	add_child(_perf)
	_perf.set_shown(world.overlay_flags().get(OVERLAY_REGISTRY.PERF, false))
	_toggles.overlay_toggled.connect(func(flag: String, on: bool):
		if flag == OVERLAY_REGISTRY.PERF:
			if is_instance_valid(_perf):
				_perf.set_shown(on)
		elif is_instance_valid(_session.world):
			_session.world.set_overlay(flag, on))


## Record the verdict per test id for the browser's marks.
func _remember(result: Dictionary) -> void:
	var results: Dictionary = Engine.get_meta(TestCatalog.META_RESULTS, {})
	results[result["id"]] = result["status"]
	Engine.set_meta(TestCatalog.META_RESULTS, results)


## Print one verdict as a batch run does (tools/play_tests.sh reads them).
func _print_result(result: Dictionary) -> void:
	TestSessionScript.print_result(result, _session.bundle_dir)


## The value of a `--name=value` argument, or `fallback`.
func _option(args: PackedStringArray, option_name: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(option_name + "="):
			return a.substr(option_name.length() + 1)
	return fallback
