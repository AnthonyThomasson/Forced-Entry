class_name VonBlockingAsk
extends RefCounted
## AI DECISION sub-domain: one round-trip to the Von server that stalls the main thread until the
## server answers. It is the ask of a test run LIVE or RECORDING (`DecisionStub`): a stalled main
## thread is the simulation held (`GameClock` counts frames, so no game time passes), and the
## answer then lands on the frame the stub fixes, the same frame a replay delivers it on. The game
## itself and the transport tests keep the asynchronous `HTTPRequest` in `decision_client.gd`.

## Microseconds slept between two polls of the connection.
const POLL_USEC := 500
## Wall seconds an ask waits for the server.
const TIMEOUT_S := 10.0


## Ask Von `question` over `options` (id → description) for `state` and wait for its answer:
## `{ pick, probabilities }` (offered ids), or `{ error }` when no usable answer came.
static func ask(
	url: String,
	model: String,
	state: String,
	question: String,
	options: Dictionary,
) -> Dictionary:
	var reply := post(
		url, JSON.stringify(VonWire.request_body(model, state, question, options)), TIMEOUT_S,
	)
	if not reply["ok"]:
		return { "error": reply["error"] }
	if reply["code"] != 200:
		return { "error": "HTTP %d: %s" % [reply["code"], _detail(reply["body"])] }
	var answer := VonWire.read_answer(reply["body"], options)
	return answer if not answer.is_empty() else { "error": "no offered option in the answer" }


## POST `body` (JSON text) to `url` and wait for the reply, at most `timeout_s` seconds of wall
## time. Returns `{ ok, code, body, error }`: `ok` when a reply came (whatever its code), its
## HTTP `code` and `body` bytes; otherwise `error` says what went wrong.
static func post(url: String, body: String, timeout_s: float) -> Dictionary:
	var target := _split(url)
	var http := HTTPClient.new()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var failure := ""
	if http.connect_to_host(target["host"], target["port"]) != OK:
		failure = "could not connect to %s" % url
	elif not _settle(http, [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING], deadline):
		failure = "timed out connecting to %s" % url
	elif http.get_status() != HTTPClient.STATUS_CONNECTED:
		failure = "no server at %s" % url
	elif http.request(HTTPClient.METHOD_POST, target["path"], headers, body) != OK:
		failure = "request failed to start"
	elif not _settle(http, [HTTPClient.STATUS_REQUESTING], deadline):
		failure = "timed out waiting for %s" % url
	var reply := PackedByteArray()
	while failure == "" and http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		reply.append_array(http.read_response_body_chunk())
		if _late(deadline):
			failure = "timed out reading the reply of %s" % url
		else:
			OS.delay_usec(POLL_USEC)
	if failure == "" and http.get_status() not in [
		HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED,
	]:
		failure = "the connection to %s failed" % url
	if failure != "":
		return { "ok": false, "code": 0, "body": PackedByteArray(), "error": failure }
	return { "ok": true, "code": http.get_response_code(), "body": reply, "error": "" }


## Poll `http` while its status is one of `busy`; false when `deadline` (ms) passed first.
static func _settle(http: HTTPClient, busy: Array, deadline: int) -> bool:
	while http.get_status() in busy:
		http.poll()
		if _late(deadline):
			return false
		OS.delay_usec(POLL_USEC)
	return true


## The text of a reply body, trimmed.
static func _detail(body: PackedByteArray) -> String:
	return body.get_string_from_utf8().strip_edges().left(200)


## `url` as host, port and path (`http://127.0.0.1:8000/v1/systemone`).
static func _split(url: String) -> Dictionary:
	var rest := url.trim_prefix("http://")
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var colon := hostport.rfind(":")
	return {
		"host": hostport if colon < 0 else hostport.substr(0, colon),
		"port": 80 if colon < 0 else int(hostport.substr(colon + 1)),
		"path": "/" if slash < 0 else rest.substr(slash),
	}


## Whether wall time `deadline` (ms) has passed.
static func _late(deadline: int) -> bool:
	return Time.get_ticks_msec() > deadline
