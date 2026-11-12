class_name VonWire
extends RefCounted
## AI DECISION sub-domain: the shape of one Von request and its answer, shared by the asynchronous
## client (`decision_client.gd`) and the blocking ask of a live test run (`VonBlockingAsk`).


## The request body: `state` text and ONE `choice` question, `instructions`, over `options`
## (id → description), for `model`.
static func request_body(
	model: String,
	state: String,
	instructions: String,
	options: Dictionary,
) -> Dictionary:
	return {
		"model": model,
		"state": state,
		"questions": {
			"pick": { "type": "choice", "instructions": instructions, "criteria": options },
		},
	}


## The offered id Von ranks highest in `answer` (its `pick` answer): its argmax `choice` when that
## is one of the offered `options`, else the highest-probability offered id. Von's distributions are
## often flat (low confidence), so taking the top pick, not sampling, keeps the NPC decisive instead
## of jittering. Empty when no offered option is present.
static func pick_from(answer: Variant, options: Dictionary) -> String:
	if not answer is Dictionary:
		return ""
	var choice = answer.get("choice")
	if choice is String and options.has(choice):
		return choice
	if not answer.get("probabilities") is Dictionary:
		return ""
	var best := ""
	var best_p := -1.0
	for id in answer["probabilities"]:
		if options.has(id) and float(answer["probabilities"][id]) > best_p:
			best_p = float(answer["probabilities"][id])
			best = id
	return best


## Von's answer to the offered `options` read from a 200 reply `body`: `{ pick, probabilities }`, or
## `{}` when the reply is malformed or offers none of them.
static func read_answer(body: PackedByteArray, options: Dictionary) -> Dictionary:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		return {}
	var answer = data["answers"].get("pick")
	var pick := pick_from(answer, options)
	if pick == "":
		return {}
	var probs: Dictionary = answer.get("probabilities", {}) if answer is Dictionary else {}
	return { "pick": pick, "probabilities": probs }
