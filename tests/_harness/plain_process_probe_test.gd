extends GameTest
## Harness probe, the plain counterpart of own_process_probe (tools/test_log_gate.py): it passes and
## says which engine process played it (appended to the file GAME_TEST_PID_LOG names).


func describe() -> Dictionary:
	return {
		"name": "Plain process probe",
		"tags": ["harness"],
		"internal": true,
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
		f.store_line("plain %d" % OS.get_process_id())
	t.check(true, "ran")
