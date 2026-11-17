extends GameTest
## Harness self-test: a test that pins its own `Settings.path` and `debug` (`set_static`)
## wins over the runner's scratch-file default, which is applied first.


func describe() -> Dictionary:
	return {
		"name": "A test's own Settings statics win over the runner's defaults",
		"tags": ["harness", "statics", "settings"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", "user://settings_harness_pin.json")
	s.set_static(Settings, &"debug", false)


func run(t: TestContext) -> void:
	await t.frames(2)
	t.expect_eq(Settings.path, "user://settings_harness_pin.json", "the test's own path wins")
	t.check(not Settings.debug, "the test's own Debug wins")
