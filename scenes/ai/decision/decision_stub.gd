class_name DecisionStub
extends RefCounted
## AI DECISION sub-domain: a stand-in for the Von server, used by game tests. While `active`,
## decision_client.gd answers every `ask()` from here instead of making an HTTP request, so the
## perception → decision → behaviour wiring can be tested without a live server. `mode` says how:
## - SCRIPT (default): the picks a test scripted. `rules` is an ordered list of
##   `{ pick: String, question: String (optional) }`: the first rule whose `pick` is among the
##   offered option ids (and whose `question` text, when given, occurs in the level's question)
##   wins;
##   with no matching rule the first offered id is taken. `fail` makes every ask fail, as if the
##   server were down; `latency_frames` holds an answer back like a slow server.
## - REPLAY: the answer recorded for the ask (`recording`, a `VonRecording`) by its `VonKey`; an ask
##   the recording lacks fails and is kept in `misses` for the session to fail the test with.
## - LIVE: the real server answers, the main thread stalled until it does (`VonBlockingAsk`).
## - RECORD: LIVE, and each answer is added to `recording`, which the session writes to the test's
##   file. An ask that gets no answer is kept in `faults`.
## In REPLAY, LIVE and RECORD the answer lands exactly `hold_frames` physics frames after the ask
## (the NPC carries on with its old order meanwhile), however long Von took: the three play the same
## frames. `source` replaces the server in LIVE and RECORD with a callable
## `(state, question, options) -> { pick, probabilities }` (`{}`: no answer), for tests of the seam.
## `requests` logs each ask as `{ state, question, options: Array, pick }`.

enum Mode {
	SCRIPT,
	REPLAY,
	LIVE,
	RECORD,
}

## Physics frames a replayed, live or recorded answer is held after its ask: about 200 ms at 60 fps.
const HOLD_FRAMES := 12

## Answer from this stub instead of the server.
static var active := false
## Fail every ask (the server-down path).
static var fail := false
static var rules: Array = []
static var requests: Array = []
## Physics frames a scripted answer is held back, like a slow server (0 = the next frame). The old
## leaf keeps running meanwhile.
static var latency_frames := 0
## How asks are answered.
static var mode := Mode.SCRIPT
## Physics frames a REPLAY, LIVE or RECORD answer is held after its ask.
static var hold_frames := HOLD_FRAMES
## The recording replayed (REPLAY) or filled (RECORD).
static var recording: VonRecording = null
## Asks (`{ state, question, options }`) a REPLAY recording had no answer for.
static var misses: Array = []
## Reasons (text) a LIVE or RECORD ask got no answer.
static var faults: Array = []
## Answers LIVE and RECORD asks instead of the server, when valid.
static var source := Callable()


## The id to answer `options` (id → description) with, or "" when `fail` is set. Logs the request.
static func answer(state: String, question: String, options: Dictionary) -> String:
	var pick := ""
	if not fail:
		pick = String(options.keys()[0]) if not options.is_empty() else ""
		for rule in rules:
			if (options.has(rule["pick"])
					and (not rule.has("question") or question.containsn(rule["question"]))):
				pick = rule["pick"]
				break
	_log(state, question, options, pick)
	return pick


## Whether the answers come from a recording or a server (not from a script): the asks the fixed
## hold applies to.
static func holds() -> bool:
	return mode != Mode.SCRIPT


## The answer of a REPLAY, LIVE or RECORD ask: `{ pick, probabilities }` (offered ids), `{}` when
## there is none (a replay miss, or a live ask that got no answer: noted in `misses` / `faults`).
## `url` and `model` are the server a LIVE or RECORD ask goes to. A live ask stalls the main thread
## here until Von answers.
static func decide(
	state: String,
	question: String,
	options: Dictionary,
	url: String,
	model: String,
) -> Dictionary:
	var out := {}
	if mode == Mode.REPLAY:
		out = _replayed(state, question, options)
		if out.is_empty():
			misses.append({ "state": state, "question": question, "options": options.duplicate() })
	else:
		out = _live(state, question, options, url, model)
		if out.has("error"):
			faults.append("%s — %s" % [question, out["error"]])
			out = {}
		elif mode == Mode.RECORD and recording != null:
			recording.add(state, question, options, out["pick"], out["probabilities"])
	_log(state, question, options, out.get("pick", ""))
	return out


## The recorded answer to the ask under the ids it offers now, `{}` when there is none.
static func _replayed(state: String, question: String, options: Dictionary) -> Dictionary:
	if recording == null:
		return {}
	var entry := recording.lookup(state, question, options)
	if entry.is_empty():
		return {}
	var pick := VonKey.offered_id(String(entry.get("pick", "")), options)
	if pick == "":
		return {}
	var probs: Dictionary = entry.get("probabilities", {})
	return { "pick": pick, "probabilities": VonKey.offered_probabilities(probs, options) }


## Von's answer, from `source` or the server: `{ pick, probabilities }` or `{ error }`.
static func _live(
	state: String,
	question: String,
	options: Dictionary,
	url: String,
	model: String,
) -> Dictionary:
	if source.is_valid():
		var got: Dictionary = source.call(state, question, options)
		return got if not got.is_empty() else { "error": "the answer source gave none" }
	return VonBlockingAsk.ask(url, model, state, question, options)


## Log one ask in `requests`.
static func _log(state: String, question: String, options: Dictionary, pick: String) -> void:
	requests.append({
		"state": state,
		"question": question,
		"options": options.keys(),
		"pick": pick,
	})
