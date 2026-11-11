extends GameTest
## Fixture for tests/_harness/von_session_test.gd, not a test of its own (its name does not end in
## `_test`, so the catalog never lists it): a requires_von test whose world asks Von three questions
## through a `DecisionClient` and logs what came back and on which physics frame. Two of them are in
## its recording (`ask_fixture.von.json`); the third, asked when `extra_ask` is set, is not.

const DecisionClient = preload("res://scenes/ai/decision/decision_client.gd")

## One entry per ask: `{ offered, pick, probabilities, asked, answered, failed }` (frames: physics
## frames; `offered` the option ids).
static var asked: Array = []
## Whether the run also asks the question its recording lacks.
static var extra_ask := false


func describe() -> Dictionary:
	return {
		"name": "Von ask fixture",
		"tags": ["harness", "von"],
		"internal": true,
		"requires_von": true,
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	# far from the world of the test that plays it: both are on the one navigation map
	s.arena(Rect2(5000, 5000, 200, 200))


func run(t: TestContext) -> void:
	asked = []
	var client := DecisionClient.new()
	client.configure("http://127.0.0.1:9/none", "von-fixture", 3.0, "Fixture")
	t.world.add_child(client)
	var first := _stand_in(t)
	var second := _stand_in(t)
	await _ask(t, client, "You are in the kitchen.", "What do you do?", {
		"a": "shoot the intruder", "b": "hide behind the table",
	})
	await _ask(t, client, "Two intruders are in view.", "Who do you fight first?", {
		"t_%d" % first: "Dana, close, in the open", "t_%d" % second: "Rob, far, behind a door",
	})
	if extra_ask:
		await _ask(t, client, "A fact the recording lacks.", "What now?", {
			"a": "one", "b": "two",
		})
	t.check(not asked.is_empty(), "the fixture asked")


## A node that holds a spawn order in the world, standing in for a character: its instance id.
func _stand_in(t: TestContext) -> int:
	var node := Node.new()
	t.world.add_child(node)
	WorldRng.enrol(node)
	return node.get_instance_id()


## Ask `client` and wait for its answer or failure, logging both with their frames.
func _ask(
	t: TestContext,
	client: Node,
	state: String,
	question: String,
	options: Dictionary,
) -> void:
	var got := {
		"offered": options.keys(), "pick": "", "probabilities": {},
		"asked": Engine.get_physics_frames(),
		"answered": -1, "failed": false,
	}
	asked.append(got)
	client.answered.connect(func(pick: String, probs: Dictionary):
		got["pick"] = pick
		got["probabilities"] = probs
		got["answered"] = Engine.get_physics_frames(),
	CONNECT_ONE_SHOT)
	client.failed.connect(func(): got["failed"] = true, CONNECT_ONE_SHOT)
	client.ask(state, question, options)
	await t.until(func(): return got["answered"] >= 0 or got["failed"], 2.0)
