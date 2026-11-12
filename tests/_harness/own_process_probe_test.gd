extends GameTest
## Harness probe for `own_process` (tools/test_log_gate.py): it passes whenever it runs and says
## which engine process played it (appended to the file GAME_TEST_PID_LOG names), so the tool test
## can tell that the runner gave each run of it a process of its own, apart from the one playing the
## plain tests. With GAME_TEST_OWN_FAIL set it fails, so the tool test can see that a failure in the
## extra process fails the run.


func describe() -> Dictionary:
	return {
		"name": "Own process probe",
		"tags": ["harness"],
		"internal": true,
		"own_process": true,
		"timeout": 2.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	var path := OS.get_environment("GAME_TEST_PID_LOG")
	if path != "":
		var f := FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open(path, FileAccess.WRITE)
		f.seek_end()
		f.store_line("own %d" % OS.get_process_id())
	t.check(OS.get_environment("GAME_TEST_OWN_FAIL") == "", "ran")
