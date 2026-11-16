extends GameTest
## Harness self-test: a test that names no `Settings.path` never reaches the developer's live
## settings file. The runner points `Settings.path` at a scratch file before `configure`'s statics,
## so a `Main` put in the tree reads and writes the scratch file, never the live one. The test names
## `Settings.debug` (the example static) so that it is put back after it, as every static a test
## names is (`settings_default_b_test`).


func describe() -> Dictionary:
	return {
		"name": "A test reads a scratch settings file, never the live one",
		"tags": ["harness", "statics", "settings"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"debug", true)


func run(t: TestContext) -> void:
	await t.frames(2)
	# Checked first, and the test ends on a miss: a save below would overwrite the live file.
	if not t.require(
		Settings.path.begins_with("user://test_scratch/"),
		"Settings.path is the runner's scratch file, not the live one",
	):
		return
	# A save lands in the scratch file, and a Debug switched off there is read back from there only.
	Settings.set_debug(false)
	t.check(FileAccess.file_exists(Settings.path), "a save wrote the scratch file")
	Settings.debug = true
	Settings.load_file()
	t.check(not Settings.debug, "load_file read the scratch file's Debug off back")
	# Left off on purpose, as a test that assigns it plainly would: the runner must put it back for
	# the next test (settings_default_b_test).
	Settings.debug = false
