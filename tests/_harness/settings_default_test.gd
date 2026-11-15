extends GameTest
## Harness self-test: a test that names no `Settings` statics never reaches the developer's live
## settings file. The runner points `Settings.path` at a scratch file and the render at 2D before
## `configure`'s statics, so a `Main` put in the tree reads neither the live path nor a saved "3d".


func describe() -> Dictionary:
	return {
		"name": "A test reads a scratch settings file, in 2D, never the live one",
		"tags": ["harness", "statics", "settings"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	# Checked first, and the test ends on a miss: a save below would overwrite the live file.
	if not t.require(
		Settings.path.begins_with("user://test_scratch/"),
		"Settings.path is the runner's scratch file, not the live one",
	):
		return
	t.expect_eq(Settings.render_mode, "2d", "the render is 2D unless the test says otherwise")
	# A save lands in the scratch file, and a "3d" saved there is read back from there only.
	Settings.set_render_mode(Settings.RENDER_3D)
	t.check(FileAccess.file_exists(Settings.path), "a save wrote the scratch file")
	Settings.render_mode = Settings.RENDER_2D
	Settings.load_file()
	t.expect_eq(Settings.render_mode, "3d", "load_file read the scratch file's 3d back")
	# Left at 3D on purpose, as a test that assigns it plainly would: the runner's default must
	# put it back for the next test (settings_default_b_test).
	Settings.render_mode = Settings.RENDER_3D
