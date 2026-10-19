extends GameTest
## Harness probe for a `requires_von` test (tools/test_log_gate.py): it passes whenever it runs. It
## runs only with `--include-von` and a live Von server; with no server it is SKIPPED, and FAILs
## under `--require-von`. The test makes "no server" with the GAME_TEST_VON_PORT seam (the runner's
## Von launcher probes that port and never starts one).


func describe() -> Dictionary:
	return {
		"name": "Von probe",
		"tags": ["harness", "von"],
		"internal": true,
		"requires_von": true,
		"timeout": 2.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.seconds(0.1)
	t.check(true, "ran with a live Von server")
