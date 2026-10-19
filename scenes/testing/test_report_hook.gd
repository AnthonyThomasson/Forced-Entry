extends GdUnitTestSessionHook
## Testing domain: the gdUnit4 session hook of a game test run (registered in project.godot,
## `gdunit4/hooks/session_hooks`). Inert unless the run was given `--out=<dir>` (tools/run_tests.sh
## always is): it then starts the run (test_batch.gd `begin`: gdUnit's log monitor on the run's
## log, the game's log quiet, `--seed`, the banner), makes a verdict record of each case of a
## selected native suite (unit_suite.gd) from gdUnit's events and prints it as a game test's, and
## at the end prints the strays, the FLAKY lines, the slowest tests and the totals and writes
## <dir>/report.json (`finish`). The game test suites keep their own records (game_test_suite.gd).
##
## With `--out` or without, it also keeps a run of the editor's GdUnit panel in step with the
## command line:
## - The panel's run (gdUnit's editor runner, `GdUnitTestRunner.gd`) is started by gdUnit without
##   `--fixed-fps`, and no option reaches it, so the engine paces it to the clock: it could run
##   several physics frames in one main-loop iteration to catch up, before any process frame (a test
##   waiting `t.frames(2)` for an overlay drawn in `_process` would see nothing yet), and it holds
##   frames to the display while vsync is on. For that run it steps physics at most once an
##   iteration (`Engine.max_physics_steps_per_frame` 1) and turns vsync off, both put back at the
##   end, so it gives the verdicts of `tools/run_tests.sh --windowed`. A lagging panel run then
##   slows its sim rather than catching up, the same as under `--fixed-fps`. (A frame budget
##   measures the iteration a frame ran in, perf_probe.gd, so the pacing waits between are not
##   counted.)
## - gdUnit writes a run's JUnit and HTML reports to `res://reports/` unless told otherwise
##   (`-rd`, which run_tests.sh always gives and the panel never does). A run left on that default
##   writes them to `user://gdunit_reports/` instead, so a panel run leaves the checkout as it was.

const TestBatch = preload("res://scenes/testing/test_batch.gd")
## The runner the editor's GdUnit panel starts (its Run and Debug), never given `--fixed-fps`.
const EDITOR_RUNNER := "res://addons/gdUnit4/src/core/runners/GdUnitTestRunner.gd"
## gdUnit's report folder when a run names none (GdUnitTestSessionRunner.gd, `report_base_path`).
const DEFAULT_REPORTS := "res://reports"
## Where a run left on that default writes its reports instead.
const OUTSIDE_REPORTS := "user://gdunit_reports"

## gdUnit's report text carries BBCode for its own console; a record keeps the plain words.
var _bbcode := RegEx.create_from_string("\\[/?(color|bgcolor|b|i|u|font_size)(=[^\\]]*)?\\]")
## The session of a run given `--out`, whose test events make the records (null otherwise).
var _session: GdUnitTestSession = null
## What a panel run changed, to put back at its end: `{ steps, vsync }` ({} for any other run).
var _paced := {}


func _init() -> void:
	super(
		"Game test report",
		"Writes report.json and prints the summary of a tools/run_tests.sh run (scenes/testing)",
	)


func startup(session: GdUnitTestSession) -> GdUnitResult:
	if _editor_runner():
		_step_like_fixed_fps()
	var base := session.report_path.get_base_dir().simplify_path()
	if base == ProjectSettings.globalize_path(DEFAULT_REPORTS).simplify_path():
		# The reporters read it at shutdown, after this hook (gdUnit shuts hooks down in reverse).
		session.report_path = ProjectSettings.globalize_path(OUTSIDE_REPORTS).path_join(
			session.report_path.get_file(),
		)
	if TestBatch.reporting():
		_session = session
		session.test_event.connect(_on_test_event)
		TestBatch.begin()
	return GdUnitResult.success()


func shutdown(session: GdUnitTestSession) -> GdUnitResult:
	if TestBatch.reporting():
		session.test_event.disconnect(_on_test_event)
		TestBatch.finish()
	if not _paced.is_empty():
		Engine.max_physics_steps_per_frame = _paced["steps"]
		if _paced.has("vsync"):
			DisplayServer.window_set_vsync_mode(_paced["vsync"])
		_paced = {}
	return GdUnitResult.success()


## Whether this run is the editor's (the GdUnit panel's), from the runner gdUnit registers.
func _editor_runner() -> bool:
	var runner: Object = Engine.get_meta("GdUnitRunner", null)
	return runner != null and runner.get_script().resource_path == EDITOR_RUNNER


## One physics step per main-loop iteration and vsync off, as a `--fixed-fps` run has them, the
## old values kept for `shutdown`.
func _step_like_fixed_fps() -> void:
	_paced = { "steps": Engine.max_physics_steps_per_frame }
	Engine.max_physics_steps_per_frame = 1
	if DisplayServer.get_name() != "headless":
		_paced["vsync"] = DisplayServer.window_get_vsync_mode()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


## A native suite's case ended: keep and print its record.
func _on_test_event(event: GdUnitEvent) -> void:
	if event.type() != GdUnitEvent.TESTCASE_AFTER:
		return
	var test := _session.find_test_by_id(event.guid())
	if test == null or not TestBatch.native_suites.get(test.suite_resource_path, false):
		return
	var entry := TestBatch.native_entry(test.suite_resource_path)
	var checks: Array = []
	var reason := ""
	for report in event.reports():
		var text := _bbcode.sub(report.message(), "", true)
		if report.is_skipped():
			reason = text
		else:
			checks.append({ "ok": false, "message": text })
	var status := ("SKIPPED"
			if event.is_skipped()
			else ("FAIL" if event.is_failed() or event.is_error() else "PASS"))
	TestBatch.add({
		"id": entry["id"] + TestBatch.NATIVE_SEP + test.test_name, "name": test.display_name,
		"domain": entry["domain"], "status": status, "reason": reason, "time": 0.0,
		"checks": checks, "logs": [], "manual": false, "wall_ms": event.elapsed_time(),
	})
