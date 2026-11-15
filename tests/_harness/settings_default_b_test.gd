extends GameTest
## Harness self-test, second of an ordered pair (runs after settings_default_test, which saved a
## settings file): the scratch file is deleted when that test's statics are restored.

const TestWorld := preload("res://scenes/testing/test_world.gd")


func describe() -> Dictionary:
	return {
		"name": "The scratch settings file of the test before is deleted",
		"tags": ["harness", "statics", "settings"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	t.expect_eq(Settings.path, TestWorld.settings_scratch(), "the default path is the scratch file")
	t.check(not FileAccess.file_exists(Settings.path), "the test before left no file behind")
