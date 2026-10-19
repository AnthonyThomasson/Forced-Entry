class_name GameTestSuite
extends GdUnitTestSuite
## Testing domain: the gdUnit4 base suite of the game tests. A wrapper suite
## (`tests/<domain>/<domain>_suite.gd`, one per AI topic folder, and the harness's
## `tests/_harness/harness_suite.gd`) lists its folder's catalog tests as the cases of one
## parameterized test and runs each unchanged:
##  @warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
##  func test_projectile(id: String, test_parameters := cases("projectile")) -> void:
##      await run_case(id)
## `run_case` plays the test as the in-game runner does (test_session.gd: its world, sim clock and
## timeout, its checks and the log gate, which ends it at once) and maps its verdict to gdUnit's:
## FAIL and TIMEOUT fail with the failed checks; SKIPPED is skipped with its reason; GAP is skipped
## as "gap: expected to fail" with its failed checks; a gap test that passes FAILs ("drop the gap
## tag"). Each verdict is also kept as a record and printed as the batch runner printed it
## (test_batch.gd), and a requires_von test waits for the Von decision server, one launcher for the
## whole process, paced in real time. A suite joins the group `game_test_suites` and exposes the
## open test's descriptor and context as `open_entry` / `open_ctx`, the hook the coverage tool's
## probe reads. The log gate is this domain's alone: gdUnit's own log scan
## (`gdunit4/report/godot/script_error`, off in project.godot) reads the project's log path, not the
## `--log-file` a run owns, so it would blame a test for another Godot's errors. A run of the
## editor's GdUnit panel, which gdUnit starts without `--fixed-fps`, is stepped once a main-loop
## iteration like one with it, and its reports kept out of the checkout (test_report_hook.gd).

const TestBatch = preload("res://scenes/testing/test_batch.gd")
const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const TestSessionScript = preload("res://scenes/testing/test_session.gd")
const CameraScript = preload("res://scenes/general/camera_controller.gd")
## The group every game test suite joins (the coverage probe finds the open test through it).
const GROUP := &"game_test_suites"

## The open test's descriptor ({} between tests): read by name, from outside, by the coverage
## probe; nothing here uses it.
var open_entry: Dictionary:
	get:
		return _session.entry if is_instance_valid(_session) and _session.ctx != null else {}
## The open test's context (null between tests): read by name, from outside, by the coverage probe;
## nothing here uses it.
var open_ctx: TestContext:
	get:
		return _session.ctx if is_instance_valid(_session) else null
## The test session that plays this suite's cases, one at a time (made in `before`).
var _session: Node = null
## The game camera this suite frames each test's world with.
var _camera: Camera2D = null


func _init() -> void:
	add_to_group(GROUP)


## The case list of a wrapper suite: the selected tests of the folder under tests/
## (TestBatch.cases).
static func cases(folder: String) -> Array:
	return TestBatch.cases(folder)


func before() -> void:
	_session = TestSessionScript.new()
	_session.name = "TestSession"
	_session.watch = TestBatch.watch()
	_session.stray_logs = TestBatch.stray_logs
	_session.include_von = TestBatch.flag("--include-von") or not TestBatch.selecting()
	_session.require_von = TestBatch.flag("--require-von")
	_session.shots = TestBatch.flag("--shots")
	_session.bundle_dir = TestBatch.bundle_dir()
	# one launcher, and the server it started, for the whole process
	_session.launcher_parent = get_tree().root
	add_child(_session)
	_session.world_built.connect(_on_world_built)
	_camera = CameraScript.new()
	_camera.name = "TestCamera"
	# it only ever frames a test's actors; its follow target must be a Node2D
	_camera.target_path = ^"."
	_camera.pan_enabled = false
	add_child(_camera)


func after() -> void:
	for n in [_session, _camera]:
		if is_instance_valid(n):
			n.free()
	_session = null
	_camera = null


## Play the catalog test `id` (e.g. `projectile/pistol_shot_wounds`) unchanged and report its
## verdict to gdUnit.
func run_case(id: String) -> void:
	if TestBatch.stopped:
		_skip("--fail-fast: the run stopped at an earlier failure")
		return
	if TestBatch.skipped_before(id):
		_skip("skipped (a repeat of a skipped test)")
		return
	var entry := TestCatalog.describe("%s/%s%s" % [TestCatalog.ROOT, id, TestCatalog.SUFFIX])
	var started := Time.get_ticks_msec()
	_session.poll_logs()  # what was logged before the test opens is no test's
	await _session.start(entry)
	var r: Dictionary = await _session.close()
	r["wall_ms"] = Time.get_ticks_msec() - started
	TestBatch.add(r)
	_report(r)


## gdUnit minimises its window at start and after every suite: bring it back and frame the world, so
## it can be watched.
func _on_world_built(_setup: TestSetup) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()
	_camera.make_current()
	_camera.frame(_session.camera_targets())


## Map a verdict record to gdUnit's.
func _report(r: Dictionary) -> void:
	var failed: Array = r["checks"].filter(func(c): return not c["ok"]).map(
		func(c): return "✗ " + String(c["message"]),
	)
	match r["status"]:
		"FAIL", "TIMEOUT":
			fail("\n".join([
				"%s %s%s" % [
					r["status"],
					r["id"],
					"" if r["reason"] == "" else "  — " + String(r["reason"]),
				],
			] + failed))
		"SKIPPED":
			_skip(String(r["reason"]))
		"GAP":
			_skip("\n".join(["gap: expected to fail"] + failed))


## Mark the running case skipped, with `reason`.
func _skip(reason: String) -> void:
	GdUnitThreadManager.get_current_context().get_execution_context().test_case.do_skip(
		true, reason,
	)
