extends GameTest
## Harness probe for the "an engine error or warning fails the test" gate (tools/test_log_gate.py).
## It passes unless the environment variable GAME_TEST_PROBE is `error` or `warning`, in which case
## it logs that on purpose and does NOT declare it, so the run must report FAIL: in batch
## (`tools/run_tests.sh --self-test`) and in the in-game runner (`-- --play log gate probe`),
## headless or windowed. With GAME_TEST_PROBE_AFTER=<file> it logs only once that file exists, and
## says `probe waiting for <file>` first: a tool test (tools/tests/test_runner_own_log.py) starts
## another Godot in between.


func describe() -> Dictionary:
	return {
		"name": "Log gate probe",
		"tags": ["harness", "log"],
		"internal": true,
		"timeout": 60.0 if OS.get_environment("GAME_TEST_PROBE_AFTER") != "" else 4.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	var after := OS.get_environment("GAME_TEST_PROBE_AFTER")
	if after != "":
		print("probe waiting for " + after)
		# a frame takes 50 ms of wall time, so another process has time to start meanwhile
		await t.until(func():
			OS.delay_msec(50)
			return FileAccess.file_exists(after), 50.0)
	match OS.get_environment("GAME_TEST_PROBE"):
		"error":
			push_error("gate probe error")
		"warning":
			push_warning("gate probe warning")
	await t.seconds(0.5)
	t.check(true, "reached the end")
