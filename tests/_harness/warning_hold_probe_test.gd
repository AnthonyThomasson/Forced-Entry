extends GameTest
## Harness probe for "a logged warning ends the test at once" (tools/test_log_gate.py). It passes
## unless the environment variable GAME_TEST_HOLD is `warning`: it then logs a warning it does not
## declare and waits far longer than any run would, under a timeout further off still, so only the
## log gate ending it on the spot gives a verdict soon (FAIL, at about 0.1 s of sim time).


func describe() -> Dictionary:
	return {
		"name": "Warning hold probe",
		"tags": ["harness", "log"],
		"internal": true,
		"timeout": 100_000.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	if OS.get_environment("GAME_TEST_HOLD") == "warning":
		push_warning("gate probe hold warning")
		await t.seconds(50_000.0)
	t.check(true, "reached the end")
