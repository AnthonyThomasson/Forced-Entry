class_name UnitSuite
extends GdUnitTestSuite
## Testing domain: the base of a native gdUnit4 suite of pure logic
## (`tests/<domain>/<name>_suite.gd`, gdUnit's own asserts, no world). Every engine error or warning
## logged while one of its tests runs fails that test, as in a game test (log_watch.gd); one logged
## between its tests is a stray of the run. It runs whole or not at all: the selection
## tools/run_tests.sh passes (`--domain`, `--skip-domain`, `--id` naming the suite or one of its
## cases, filter words on its path and name) is decided per suite (test_batch.gd `native_selected`),
## and a suite left out is skipped, quietly: its cases leave no record. The selected ones become
## records through the run's session hook (test_report_hook.gd), each
## `<path under tests/, no .gd>::<test function>`.

const TestBatch = preload("res://scenes/testing/test_batch.gd")
const LogWatch = preload("res://scenes/testing/log_watch.gd")
## Physics frames waited after a test before its log is read, so what its teardown logged lands on
## it.
const SETTLE_FRAMES := 2


func _init() -> void:
	var path: String = get_script().resource_path
	__is_skipped = not TestBatch.native_selected(path)
	__skip_reason = "not selected by this run"
	TestBatch.native_suites[path] = not __is_skipped


## gdUnit's per-test setup: what was logged before the test opens is a stray of the run.
func before_test() -> void:
	TestBatch.poll_strays()  # what was logged before the test opens is no test's


## gdUnit's per-test teardown: once its teardown has logged, fails the test on any engine error
## or warning logged while it ran (log_watch.gd).
func after_test() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().physics_frame
	for e in TestBatch.watch().poll(true):
		if not LogWatch.matches_any(e, []):
			var where: String = e["location"]
			fail("Logged %s: %s%s"
					% [e["severity"], e["message"], "" if where == "" else " (at %s)" % where])
