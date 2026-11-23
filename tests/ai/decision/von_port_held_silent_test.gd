extends GameTest
## Something that is not Von accepts connections on the Von port and never answers (a hung
## program, a listener that is no HTTP server). The launcher, which is NOT probe-only here, does
## not start its own server over it (that one could not bind, after loading the whole model): it
## gives up within `ready_timeout` from scene load, saying the port is held by something that does
## not answer, so the setup window opens and the NPCs hold steady. The Forced-Entry home is an
## empty folder, so a server that was started anyway would say "no Von venv" instead.

const LAUNCHER := preload("res://scenes/ai/decision/decision_server_launcher.gd")
## An unused port, so a Von running on the developer's own port is never probed.
const PORT := 18_733
## The launcher's whole budget, short for the test.
const READY_TIMEOUT_S := 8.0
## Wall-clock seconds the launcher may take over its budget (the last probe, the frame it ends in).
const SLACK_S := 4.0


func describe() -> Dictionary:
	return {
		"name": "Port held by a silent listener: no server started, a warning in time",
		"description": "A TCP listener that accepts and never writes: the launcher gives up "
			+ "within its ready_timeout and does not launch Von over it.",
		"tags": ["ai", "decision", "von", "launcher", "setup"],
		"timeout": 60.0,
		"allowed_logs": ["\\[von\\] "],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var held := TCPServer.new()
	if not t.require(held.listen(PORT, "127.0.0.1") == OK, "the stand-in listener listens"):
		return
	var home := ProjectSettings.globalize_path("user://von_port_held_silent_home")
	DirAccess.make_dir_recursive_absolute(home)
	var had_home := OS.has_environment("FORCED_ENTRY_HOME")
	var home_was := OS.get_environment("FORCED_ENTRY_HOME")
	OS.set_environment("FORCED_ENTRY_HOME", home)
	var launcher: Node = LAUNCHER.new()
	launcher.port = PORT
	launcher.echo_to_output = false
	launcher.ready_timeout = READY_TIMEOUT_S
	var verdict := { "live": true }
	launcher.resolved.connect(func(is_live: bool): verdict["live"] = is_live)
	(Engine.get_main_loop() as SceneTree).root.add_child(launcher)
	var started := Time.get_ticks_msec()
	while (
		not launcher.is_resolved()
		and Time.get_ticks_msec() - started < (READY_TIMEOUT_S + 3 * SLACK_S) * 1000.0
	):
		OS.delay_msec(20)  # Real time: the probe's timeout is wall time.
		await t.frames(1)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var problem: String = launcher.problem
	launcher.free()
	held.stop()
	if had_home:
		OS.set_environment("FORCED_ENTRY_HOME", home_was)
	else:
		OS.unset_environment("FORCED_ENTRY_HOME")
	DirAccess.remove_absolute(home)
	t.check(not verdict["live"], "no server is coming")
	t.check(
		secs < READY_TIMEOUT_S + SLACK_S,
		"it settled within its ready_timeout (%.1fs of %.0fs)" % [secs, READY_TIMEOUT_S],
	)
	t.check(problem.contains("does not answer"), "it says the port does not answer: " + problem)
	t.check(problem.contains("Port %d" % PORT), "it names the port: " + problem)
	t.check(not problem.contains("no Von venv"), "it did not start our own server: " + problem)
