extends Node
## AI DECISION sub-domain: the external-model transport. This wraps one round-trip to the local Von
## ("System One") decision server: it POSTs a state text plus ONE `choice` question over a set of
## option ids → descriptions, and resolves Von's answer into the top-ranked offered id. Von is a
## stateless single-shot ranker that scores each question independently, so the decision planner
## (decision_planner.gd) drives a multi-level walk by calling `ask()` once per level. It emits
## `answered(pick, probabilities)` on success and `failed()` on any error (request couldn't start,
## server unreachable or refusing, malformed response). It holds NO policy and never interprets ids.

## Von's top-ranked offered id for the question, plus its probability for every offered id.
signal answered(pick: String, probabilities: Dictionary)
## A request could not start, the server was unreachable or refused, or the response was malformed.
signal failed()

## The `/v1/systemone` endpoint to ask (set by the planner from the NPC's `tuning.decision`).
var server_url: String
## Model name sent with each request (set by the planner from the NPC's `tuning.decision`).
var model: String
## Client for decision requests.
var _http: HTTPRequest
## True while a request is in flight.
var _pending := false
## Option ids → descriptions of the in-flight question (to validate the pick).
var _options := {}
## Name of the driven NPC, for log lines.
var _npc_name := "NPC"
## Last failure reported, so a persistent one isn't logged every tick.
var _last_error := ""
## Which scripted ask is current: a delayed stub answer for an older one is dropped.
var _stub_serial := 0


## Configure the endpoint + request timeout and build the HTTP client. Called once by the planner.
func configure(url: String, model_name: String, timeout: float, npc_name: String = "NPC") -> void:
	server_url = url
	model = model_name
	_npc_name = npc_name
	_http = HTTPRequest.new()
	_http.timeout = timeout
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Name of the driven NPC, for log lines (known only once the controller has its character).
func set_npc_name(npc_name: String) -> void:
	_npc_name = npc_name


## POST `state_text` with one `choice` question: `instructions` over `options` (id → description).
## Returns whether the request started; on failure to start it also emits `failed()`.
func ask(state_text: String, instructions: String, options: Dictionary) -> bool:
	_options = options
	if DecisionStub.active:
		_pending = true
		_stub_serial += 1
		_answer_from_stub.call_deferred(_stub_serial, state_text, instructions, options)
		return true
	var body := VonWire.request_body(model, state_text, instructions, options)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if _http.request(server_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) == OK:
		_pending = true
		return true
	_fail("request failed to start")
	return false


## Test seam (decision_stub.gd): answer the in-flight question from the stub, a frame later like a
## real reply. A scripted answer waits `DecisionStub.latency_frames` more physics frames when a test
## wants a slow server; a replayed, live or recorded one (`DecisionStub.holds()`) is decided now
## (a live ask stalls the main thread until Von answers) and lands exactly
## `DecisionStub.hold_frames` physics frames after the ask. Dropped if the request was cancelled
## meanwhile.
func _answer_from_stub(
	serial: int,
	state_text: String,
	instructions: String,
	options: Dictionary,
) -> void:
	if not _pending or serial != _stub_serial:
		return  # cancelled before it was decided: never asked, never recorded, never a miss
	var held := DecisionStub.holds()
	var decided := {}
	if held:
		decided = DecisionStub.decide(state_text, instructions, options, server_url, model)
	for i in (DecisionStub.hold_frames if held else DecisionStub.latency_frames):
		if not is_inside_tree():
			return
		await get_tree().physics_frame
	if not _pending or serial != _stub_serial:
		return
	_pending = false
	if held:
		if decided.is_empty():
			_fail("no answer from the recording or the server")
		else:
			answered.emit(decided["pick"], decided["probabilities"])
		return
	var pick := DecisionStub.answer(state_text, instructions, options)
	if pick == "":
		_fail("scripted failure")
	else:
		answered.emit(pick, {})


## Abandon the in-flight request (its answer is no longer wanted); no signal is emitted for it.
func cancel() -> void:
	if _pending:
		_http.cancel_request()
		_pending = false


## Read the answer and emit Von's top pick; emit `failed()` on transport or parse error.
func _on_request_completed(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	_pending = false
	# A transport failure and an HTTP error answer are DIFFERENT faults and must not share a
	# message: calling a 4xx/5xx "unreachable" hides the server's own explanation (a missing model
	# checkpoint, say) behind what reads as a connection problem.
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("no reply from %s (HTTPRequest result %d)" % [server_url, result])
		return
	if code != 200:
		_fail("server refused the decision: HTTP %d — %s" % [code, error_detail(body)])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("answers") is Dictionary:
		_fail("malformed response")
		return
	var answer = data["answers"].get("pick")
	var pick := _pick(answer)
	if pick == "":
		_fail("no offered option in the answer")
		return
	_last_error = ""  # Recovered, so a later recurrence is worth reporting again.
	var probs: Dictionary = answer.get("probabilities", {}) if answer is Dictionary else {}
	answered.emit(pick, probs)


## Report a failed decision and fall back. The same `reason` is logged only ONCE: every NPC re-asks
## about once a second, so a persistent fault (a server that cannot load its weights) would
## otherwise bury the log. A different reason, or a recovery followed by a relapse, logs again.
func _fail(reason: String) -> void:
	failed.emit()
	if reason == _last_error:
		return
	_last_error = reason
	GameLog.say("%s (Von) %s — holding steady" % [_npc_name, reason])


## The server's own explanation for a non-200 (`{ "detail": … }`), so a configuration fault is
## reported as itself. Falls back to the raw body, trimmed, when it isn't that shape. The launcher's
## readiness warning reports the same way (`decision_server_launcher.gd`).
static func error_detail(body: PackedByteArray) -> String:
	var text := body.get_string_from_utf8().strip_edges()
	var data = JSON.parse_string(text)
	if data is Dictionary and data.has("detail"):
		return str(data["detail"])
	return text if text != "" else "(empty response body)"


## The offered id Von ranks highest in `answer` (`VonWire.pick_from`), "" when no offered option is
## present.
func _pick(answer: Variant) -> String:
	return VonWire.pick_from(answer, _options)
