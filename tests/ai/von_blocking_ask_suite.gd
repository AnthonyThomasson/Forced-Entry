extends UnitSuite
## Native unit suite for `VonBlockingAsk`, the ask of a live or recording test run: it stalls the
## calling thread until the server answers (the stalled main thread is the simulation held), reads
## the pick and probabilities off Von's reply, and reports a refusal, a malformed reply or no
## server as an error. A server thread on a local port plays Von; its reply takes `DELAY_MS`.

const PORT := 48_731
const DELAY_MS := 120
## How long the server thread waits for a client before it gives up.
const GIVE_UP_MS := 3000
const OPTIONS := { "a": "shoot", "b": "hide" }

var _server := TCPServer.new()
var _thread: Thread = null
var _reply := ""
var _code := 200


func before_test() -> void:
	_code = 200


func after_test() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_server.stop()


## Serve ONE request on a thread: wait for it, answer after DELAY_MS with `_code` and `_reply`.
func _serve() -> void:
	assert_int(_server.listen(PORT, "127.0.0.1")).is_equal(OK)
	_thread = Thread.new()
	_thread.start(func():
		var conn: StreamPeerTCP = null
		var waited := 0
		while conn == null and waited < GIVE_UP_MS:
			if _server.is_connection_available():
				conn = _server.take_connection()
			else:
				OS.delay_msec(2)
				waited += 2
		if conn == null:
			return
		var request := ""
		while not _complete(request):
			conn.poll()
			if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				return
			if conn.get_available_bytes() > 0:
				request += conn.get_utf8_string(conn.get_available_bytes())
			else:
				OS.delay_msec(2)
		OS.delay_msec(DELAY_MS)
		var body := _reply.to_utf8_buffer()
		var head := (
			"HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
			+ "Connection: close\r\n\r\n"
		) % [_code, body.size()]
		conn.put_data(head.to_utf8_buffer())
		conn.put_data(body)
		conn.poll()
		OS.delay_msec(20)
		conn.disconnect_from_host())


## Whether `request` holds its whole body, as its Content-Length says.
func _complete(request: String) -> bool:
	var split := request.find("\r\n\r\n")
	if split < 0:
		return false
	var length := RegEx.create_from_string("Content-Length: (\\d+)").search(request)
	return length != null and request.length() - split - 4 >= int(length.get_string(1))


func _ask() -> Dictionary:
	return VonBlockingAsk.ask(
		"http://127.0.0.1:%d/v1/systemone" % PORT, "von-test", "state", "question", OPTIONS,
	)


func test_it_waits_for_the_server_and_reads_its_pick_and_probabilities() -> void:
	_reply = JSON.stringify({ "answers": { "pick": {
		"type": "choice", "choice": "b", "probabilities": { "a": 0.25, "b": 0.75 },
	} } })
	_serve()
	var began := Time.get_ticks_msec()
	var got := _ask()
	var waited := Time.get_ticks_msec() - began
	assert_dict(got).is_equal({ "pick": "b", "probabilities": { "a": 0.25, "b": 0.75 } })
	assert_int(waited).override_failure_message(
		"it returns only once the server has answered (took %d ms)" % waited
	).is_greater_equal(DELAY_MS)


func test_the_top_probability_is_taken_when_the_choice_is_not_offered() -> void:
	_reply = JSON.stringify({ "answers": { "pick": {
		"choice": "zzz", "probabilities": { "a": 0.9, "b": 0.1 },
	} } })
	_serve()
	assert_str(_ask()["pick"]).is_equal("a")


func test_a_refusal_is_an_error_carrying_the_servers_words() -> void:
	_code = 422
	_reply = '{"detail": "weights not loaded"}'
	_serve()
	var got := _ask()
	assert_bool(got.has("pick")).is_false()
	assert_str(got["error"]).contains("422").contains("weights not loaded")


func test_a_reply_that_offers_none_of_the_options_is_an_error() -> void:
	var pick := { "choice": "q", "probabilities": { "q": 1 } }
	_reply = JSON.stringify({ "answers": { "pick": pick } })
	_serve()
	assert_bool(_ask().has("error")).is_true()


func test_no_server_is_an_error_not_a_hang() -> void:
	var got := VonBlockingAsk.ask("http://127.0.0.1:%d/x" % (PORT + 1), "m", "s", "q", OPTIONS)
	assert_bool(got.has("error")).is_true()
