extends GameTest
## Harness probe for the Von run modes through the real wrapper (tools/test_log_gate.py): a
## requires_von test that asks one question over the wire and passes when Von's answer arrives. The
## server is the port in GAME_TEST_VON_PORT (a fake one the tool test runs), its recording the file
## GAME_TEST_PROBE_RECORDING names (never a file in the repository), so `--record-von` writes one,
## a plain run replays it with no server, and `--require-von` asks the server and writes nothing.
## Without that variable it replays the recording committed beside it.

const DecisionClient = preload("res://scenes/ai/decision/decision_client.gd")


func describe() -> Dictionary:
	return {
		"name": "Von record probe",
		"tags": ["harness", "von"],
		"internal": true,
		"requires_von": true,
		"recording": OS.get_environment("GAME_TEST_PROBE_RECORDING"),
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var client := DecisionClient.new()
	var port := OS.get_environment("GAME_TEST_VON_PORT")
	client.configure(
		"http://127.0.0.1:%s/v1/systemone" % (port if port != "" else "8000"),
		"von-probe", 3.0, "Probe",
	)
	t.world.add_child(client)
	var got := { "pick": "" }
	client.answered.connect(func(pick: String, _probs: Dictionary): got["pick"] = pick)
	client.ask("You are in the kitchen.", "What do you do?", {
		"shoot": "shoot the intruder", "hide": "hide behind the table",
	})
	await t.until(func(): return got["pick"] != "", 3.0)
	t.check(["shoot", "hide"].has(got["pick"]), "Von's answer arrived: one of the offered options")
