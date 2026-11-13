extends RefCounted
## Testing domain: the test session's Von gate (test_session.gd's `von`). It decides how each
## requires_von test's decisions are answered (`mode_for`): replayed from its recording, which needs
## no server and no pacing, or live / recording / live-only, which wait here for the Von decision
## server (one launcher per process, kept under `launcher_parent` while it lives) and, once they
## run, are paced in real time (`pace`, each process frame) until `end`. It holds its session (a
## Node): the launcher goes under it when no `launcher_parent` is given. The wait is announced
## through the callable the session hands `skip_reason`, its `status` signal's `emit`.

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

## Whether a requires_von test that needs the server may run: a live-only one or one run live
## (false: it is SKIPPED, "pass --include-von"). A test that replays its recording never asks.
## The batch sets it for `--include-von`; a host with no run options leaves it.
var include := true
## Whether a requires_von test FAILs instead of skipping when no server is live (--require-von).
var require := false
## Whether requires_von tests run LIVE, against the server, instead of replaying their recordings
## (the host sets it for `--include-von` and `--require-von`).
var live := false
## Whether requires_von tests RECORD: live, each writing its recording (the host sets it for
## `--record-von`, and only that does).
var record := false
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


## How the Von test `entry` is answered (`DecisionStub.Mode`): RECORD when the run records, LIVE
## when the host asked for the server, else REPLAY of its recording. SCRIPT stands for no stub at
## all: a `live_only` test (the HTTP transport itself) always meets the real client and server.
func mode_for(entry: Dictionary) -> DecisionStub.Mode:
	if entry.get("live_only", false):
		return DecisionStub.Mode.SCRIPT
	if record:
		return DecisionStub.Mode.RECORD
	return DecisionStub.Mode.LIVE if live else DecisionStub.Mode.REPLAY


## Why the open Von test does not run live, "" when it does: skipped unless Von tests are included
## (or `force`: a recording run), else `NOT_LIVE` when the launcher finds no server. A Von test that
## runs live is paced in real time. `announce` is called with a status line for the host's banner
## while the server is awaited. A replayed test never asks.
func skip_reason(announce: Callable, force := false) -> String:
	if DecisionStub.source.is_valid():
		return ""  # a stand-in answer source replaces the server (the tests of the seam)
	if not force and not include and not require:
		return "needs the Von decision server (pass --include-von)"
	# Von answers in real time: a batch run's `--fixed-fps` sim outpaces it (game-time timers like
	# the HTTP timeout expire early), so pace this test in real time.
	_realtime = true
	if not await _await_von(announce):
		return NOT_LIVE
	return ""


## Whether the open test is paced in real time (it runs live; a replayed one never is).
func paced() -> bool:
	return _realtime


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
		_launcher.background_qos = false  # A live ask is capped at 10 s: no slowed server here.
		var port := OS.get_environment(VON_PORT_ENV)
		if port != "":
			_launcher.port = int(port)
		_launcher.resolved.connect(func(is_live: bool): _von_live = is_live)
		_von_live = false
		(launcher_parent if launcher_parent != null else _session).add_child(_launcher)
		if port != "":
			_launcher.von_path = ""
	if not _launcher.is_resolved():
		announce.call("Waiting for the decision server…")
		await _launcher.resolved
	return _von_live
