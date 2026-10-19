extends GameTest
## Harness probe for the verdicts a run reports, and gdUnit's JUnit with them
## (tools/test_log_gate.py). It passes unless the environment variable GAME_TEST_VERDICT is `fail`
## (a failed check), `timeout` (it runs past its timeout) or `skip` (it skips itself).


func describe() -> Dictionary:
	return {
		"name": "Verdict probe",
		"tags": ["harness", "verdict"],
		"internal": true,
		"timeout": 1.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	match OS.get_environment("GAME_TEST_VERDICT"):
		"fail":
			t.check(false, "verdict probe: a failed check")
			return
		"timeout":
			await t.seconds(5.0)
			return
		"skip":
			t.skip("verdict probe: skipped on purpose")
			return
	t.check(true, "reached the end")
