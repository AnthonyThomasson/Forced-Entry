extends GameTest
## Something that is not Von answers on the Von port (an HTTP server that refuses every decision):
## the launcher does not start a second server that could not bind; it settles with no server and
## says so, naming the port, the HTTP status and what to do, so the setup window opens and the NPCs
## hold steady.

const LAUNCHER := preload("res://scenes/ai/decision/decision_server_launcher.gd")
## An unused port, so a Von running on the developer's own port is never probed.
const PORT := 18_732
const NOT_FOUND := "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
const WALL_LIMIT_S := 30.0


func describe() -> Dictionary:
	return {
		"name": "Port taken by another server: no server, a warning naming the port",
		"description": "A 404-ing HTTP server on the port: the launcher gives up after its probes "
			+ "and says the server is up but cannot decide.",
		"tags": ["ai", "decision", "von", "launcher", "setup"],
		"timeout": 60.0,
		"allowed_logs": ["\\[von\\] "],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var other := TCPServer.new()
	if not t.require(other.listen(PORT, "127.0.0.1") == OK, "the stand-in server listens"):
		return
	var launcher: Node = LAUNCHER.new()
	launcher.port = PORT
	launcher.echo_to_output = false
	launcher.probe_attempts = 2
	launcher.probe_interval = 0.1
	launcher.probe_only = true  # What is on the port is not ours to replace.
	var verdict := { "live": true }
	launcher.resolved.connect(func(is_live: bool): verdict["live"] = is_live)
	(Engine.get_main_loop() as SceneTree).root.add_child(launcher)
	var peers: Array[StreamPeerTCP] = []
	var started := Time.get_ticks_msec()
	while not launcher.is_resolved() and Time.get_ticks_msec() - started < WALL_LIMIT_S * 1000.0:
		OS.delay_msec(10)
		while other.is_connection_available():
			var peer := other.take_connection()
			peer.put_data(NOT_FOUND.to_utf8_buffer())
			peers.append(peer)
		await t.frames(1)
	var problem: String = launcher.problem
	var settled: bool = launcher.is_resolved()
	launcher.free()
	other.stop()
	t.check(settled and not verdict["live"], "no server is coming")
	t.check(problem.contains("port %d" % PORT), "it names the port: " + problem)
	t.check(problem.contains("HTTP 404"), "it names the refusal: " + problem)
	t.check(problem.contains("NPCs hold steady"), "it says what the NPCs do")
