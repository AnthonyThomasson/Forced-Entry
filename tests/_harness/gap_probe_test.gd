extends GameTest
## Harness probe for a `gap` test (tools/test_log_gate.py): it fails as a gap test is meant to (GAP,
## which gdUnit shows as skipped, "gap: expected to fail"), unless the environment variable
## GAME_TEST_GAP is `pass`, when it passes and so must FAIL ("drop the gap tag").


func describe() -> Dictionary:
	return { "name": "Gap probe", "tags": ["harness", "gap"], "internal": true, "timeout": 1.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	if OS.get_environment("GAME_TEST_GAP") == "pass":
		t.check(true, "gap probe: the behaviour is there")
	else:
		t.check(false, "gap probe: the behaviour is not built")
