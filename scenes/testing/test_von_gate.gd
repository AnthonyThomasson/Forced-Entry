extends RefCounted
## Testing domain: the test session's Von gate (test_session.gd's `von`). A requires_von test waits
## here for the Von decision server (one launcher per process, kept under `launcher_parent` while it
## lives) and, once it runs, is paced in real time (`pace`, each process frame) until `end`. It
## holds its session (a Node): the launcher goes under it when no `launcher_parent` is given. The
## wait is announced through the callable the session hands `skip_reason`, its `status` signal's
## `emit`.

const LAUNCHER = preload("res://scenes/ai/decision/decision_server_launcher.gd")
## Frame rate a Von-dependent test is paced to in real time (matches the batch run's --fixed-fps
## 60).
const REALTIME_FPS := 60
## Environment variable naming the port the Von launcher probes instead of its own; with it the
## launcher never starts a server (no server there = no server), which is how tools/test_log_gate.py
## makes "no server" on purpose.
const VON_PORT_ENV := "GAME_TEST_VON_PORT"
## The skip reason of a Von test when no server is live (a failure under `--require-von`).
const NOT_LIVE := "the Von decision server is not live"

## The Von launcher, made by the first requires_von test.
static var _launcher: Node = null
## The launcher's settled answer: whether a server is live.
static var _von_live := false

## Whether requires_von tests run (false: they are SKIPPED, a batch run without --include-von).
var include := true
## Whether a requires_von test FAILs instead of skipping when no server is live (--require-von).
var require := false
## Where the Von launcher lives: it is kept, with the server it started, as long as that node does.
var launcher_parent: Node = null
## While true, each frame sleeps out the rest of 1/REALTIME_FPS of wall time (Engine.max_fps is not
## honoured under --fixed-fps headless).
var _realtime := false
## Wall time (usec) the last frame ended at, after any pacing sleep; 0 before the first.
var _last_frame_usec := 0
## The session this gate serves (the launcher's fallback parent).
var _session: Node


func _init(session: Node) -> void:
	_session = session


## Sleep out the rest of the frame while a Von test is paced in real time; the session's
## `_process` calls it every frame.
func pace() -> void:
	var now := Time.get_ticks_usec()
	if _realtime and _last_frame_usec > 0:
		var wait := int(1_000_000 / float(REALTIME_FPS)) - (now - _last_frame_usec)
		if wait > 0:
			OS.delay_usec(wait)
			now = Time.get_ticks_usec()
	_last_frame_usec = now


## Why the open Von test does not run, "" when it does: skipped unless Von tests are included, else
## `NOT_LIVE` when the launcher finds no server. A Von test that runs is paced in real time.
## `announce` is called with a status line for the host's banner while the server is awaited.
func skip_reason(announce: Callable) -> String:
	if not include and not require:
		return "needs the Von decision server (pass --include-von)"
	# Von answers in real time: a batch run's `--fixed-fps` sim outpaces it (game-time timers like
	# the HTTP timeout expire early), so pace this test in real time.
	_realtime = true
	if not await _await_von(announce):
		return NOT_LIVE
	return ""


## Stop pacing in real time (the session's `close`).
func end() -> void:
	_realtime = false


## Ensure the Von launcher exists and has settled; returns whether a server is live. With
## GAME_TEST_VON_PORT set the launcher probes that port and never starts a server: `von_path` is
## cleared after its `_ready` (which fills a blank one from the project setting) and before the
## first probe answers, the only time it reads the path. `announce` is told the wait.
func _await_von(announce: Callable) -> bool:
	if not is_instance_valid(_launcher):
		_launcher = LAUNCHER.new()
		_launcher.name = "DecisionServerLauncher"
		var port := OS.get_environment(VON_PORT_ENV)
		if port != "":
			_launcher.port = int(port)
		_launcher.resolved.connect(func(live: bool): _von_live = live)
		_von_live = false
		(launcher_parent if launcher_parent != null else _session).add_child(_launcher)
		if port != "":
			_launcher.von_path = ""
	if not _launcher.is_resolved():
		announce.call("Waiting for the decision server…")
		await _launcher.resolved
	return _von_live
