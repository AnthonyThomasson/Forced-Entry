extends Node
## AI domain: development convenience that starts a local decision-model server (Von's `von serve`)
## when the game runs from the Godot editor, and stops it when the game exits. Exported builds never
## launch it. The server is started by the project's boot script for the current OS
## (`tools/von/boot.sh` or `tools/von/boot.ps1`, start-only: they install nothing), which finds the
## Von install in the per-user Forced-Entry home itself. A server already answering on `port` is
## reused and left running, and only a server this launcher itself started is stopped on exit. Reuse
## is decided by probing `port` up to `probe_attempts` times so a slow-to-answer existing server is
## reused rather than racing into a duplicate that cannot bind the port. The server's output is
## appended to `user://von_server.log` and, when `echo_to_output` is set, printed to the editor
## Output panel as `[von] …` lines.
##
## The probe asks the server to DECIDE (see `_probe_once`), not merely to answer `GET /`, because an
## ORPHANED server is worse than an absent one. A `von serve` left behind by a hard-killed run
## (which skips `_exit_tree`) has a dead stdout pipe, so when it tries to fetch weights the progress
## output raises `EPIPE` and the load fails — permanently. It still serves HTTP, so a liveness check
## would reuse it forever while every decision 422s. Asking for a real decision catches that and
## resolves `false` with the server's own explanation. To clear such a server by hand, before
## killing its game: `tools/von_stop.sh <game pid>`.

## Emitted exactly ONCE when the server question settles: `live` is true when a server answered (NPC
## decisions will succeed), false when none is coming — a probe-only launcher, a setup that is
## missing or broken (the boot script's exit 3), a failed spawn, an exported build, or
## `ready_timeout` elapsed. Main gates the match start on this, so every terminal path
## must reach `_resolve()`: one that silently never resolved would hang the setup window forever.
signal resolved(live: bool)

## Seconds a TCP connect to `port` may take before nothing is taken to be bound there
## (`_port_open`).
const CONNECT_WAIT_S := 3.0
## Longest (s) one readiness probe waits: it is a real inference, and the first also loads the
## weights.
const PROBE_TIMEOUT_S := 15.0
## Where the server output is appended.
const LOG_PATH := "user://von_server.log"
## The readiness probe (`_probe`).
const ServerProbe := preload("res://scenes/ai/decision/server_probe.gd")
## The Von transport, whose reporting of a refused decision the probe's warning reuses (`_detail`).
const DecisionClient := preload("res://scenes/ai/decision/decision_client.gd")
## The boot script's output: its pipes drained into the log, its `von:` line kept.
const ServerOutput := preload("res://scenes/ai/decision/server_output.gd")

## Never start a server: only probe `port` and reuse what answers (the test runner's gate when it
## is pointed at another port, `TestVonGate`). With nothing live there the launcher just resolves
## `false`.
@export var probe_only: bool = false
## Port the server listens on: the NPCs' default endpoint's (`NpcDecisionTuning.SERVER_PORT`).
@export var port: int = NpcDecisionTuning.SERVER_PORT
## Compute device passed to the boot script (`von serve --device`). `cpu` is the default because
## PyTorch's Apple GPU backend (`mps`, which `auto` picks on a Mac) crashes the server on its first
## request.
@export_enum("cpu", "auto", "mps", "cuda", "openvino") var device: String = "cpu"
## Once our server answers its readiness probe, move it to macOS background QoS
## (`taskpolicy -b -p <pid>`), which keeps PyTorch's CPU bursts on the efficiency cores so they do
## not starve the game. It is applied AFTER the first answer, not at launch, so the boot and the
## readiness probe keep their full speed. The cost: Von answers slower for the rest of the run.
## Other platforms ignore it. Off for the test runner's gate, whose asks are capped at 10 s
## (`TestVonGate`). The measurements: `decision-von-server.md`.
@export var background_qos: bool = true
## Also print each server log line to the Output panel.
@export var echo_to_output: bool = true
## How many times to probe `port` before giving up on what holds it. Retries let a just-orphaned or
## briefly slow server (one that TIMES OUT) be reused. A port that REFUSES the connection has
## nothing bound to wait for, so that answer short-circuits the retries and launches our own server
## at once; one that stays silent is never launched over (it is held by something else).
@export var probe_attempts: int = 5
## Seconds between probe attempts.
@export var probe_interval: float = 0.5
## How long (s) from scene load every path may take to settle (`resolved`): the probes of a port,
## and the polling of a server we launched for its first answer, so the match can know when the
## brain is live. Model boot dominates this; it is not a hard failure, just when we stop waiting.
@export var ready_timeout: float = 180.0

## Why no server is coming, `""` while nothing is wrong (a live or reused server): the warning the
## launcher printed, with the cause and the fix. Set before `resolved(false)` fires.
var problem := ""
## Process id of the server we launched; -1 if none (including a reused server). On Windows it is
## the boot script's PowerShell, which holds the server in a kill-on-close job: ending it ends the
## server. On a Mac the boot script has become the server (`exec`).
var _pid := -1
## The boot script's output, drained into the log (`server_output.gd`; its `von: <cause>. Fix:
## <command>` line is on stderr).
var _output := ServerOutput.new()
## The readiness probe: its HTTP request (freed once the server answers or we give up), the reuse
## attempts left, and whether (and until when) we are polling a server we launched.
var _probe := ServerProbe.new()
## Scene-load time, so the ready line can report how long the brain took.
var _start_ms := 0
## Whether the server question has settled (see `resolved`).
var _resolved := false


## Probe for a running server (retrying up to `probe_attempts`), then launch one if none answers and
## poll it until it is live. This node sits at the root of `main.tscn`, so all of it runs at SCENE
## LOAD — while the pre-game setup window is still open — giving the server its whole boot time
## before the match builds any NPC.
func _ready() -> void:
	if not OS.has_feature("editor"):
		_resolve(false)  # Exported build: never auto-starts, so the match must not wait on one.
		return
	_start_ms = Time.get_ticks_msec()
	_probe.ready_deadline_ms = _start_ms + int(ready_timeout * 1000.0)
	_probe.request = HTTPRequest.new()
	_probe.request.timeout = PROBE_TIMEOUT_S
	add_child(_probe.request)
	_probe.request.request_completed.connect(_on_probe_completed)
	_probe.attempts_left = maxi(1, probe_attempts)
	_probe_once()


## Stop the server we launched (never a reused one) and wait for the reader thread to see the
## pipe close. A probe still in flight is dropped so its resumed continuation bails.
func _exit_tree() -> void:
	_end_probing()
	if _pid > 0:
		OS.kill(_pid)  # The whole server on both OSes (see `_pid`).
		_pid = -1
	_output.finish()


## Whether the server question has settled. Main checks this BEFORE awaiting `resolved`, because a
## path that resolves synchronously in `_ready()` (an exported build) fires the signal before any
## parent could connect — children are readied before their parent.
func is_resolved() -> bool:
	return _resolved


## Settle the server question once and tell anyone gating on it. Idempotent: the first answer wins.
func _resolve(live: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_probe.waiting_ready = false
	_end_probing()
	resolved.emit(live)


## Ask the server to make one throwaway decision; `_on_probe_completed` then decides reuse, retry,
## launch, or "up but useless". It POSTs to the REAL decision endpoint (`NpcDecisionTuning`'s
## `SERVER_PATH`, naming its `MODEL`) rather than a `GET /`: a `GET /` only proves something is
## listening, and a server that cannot load its weights answers that happily (200 in milliseconds)
## while refusing every actual decision. Asking it to decide is the only check that means "the brain
## works" — and it doubles as a warm-up, so the first in-match decision isn't the one paying for
## model load. Nothing bound on `port` is told apart first, by a TCP connect (`_port_open`): the
## HTTP request would take its whole timeout to give up on a closed port on Windows.
func _probe_once() -> void:
	_probe.attempts_left -= 1
	if not await _port_open():
		if _probe.request != null:
			_on_probe_completed(
				HTTPRequest.RESULT_CANT_CONNECT,
				0,
				PackedStringArray(),
				PackedByteArray(),
			)
		return
	if _probe.request == null:
		return  # The node left the tree while the connect was tried.
	# The request never outlives the deadline (but for a second): a silent port gives up in time.
	var left_s := (_probe.ready_deadline_ms - Time.get_ticks_msec()) / 1000.0
	_probe.request.timeout = clampf(left_s, 1.0, PROBE_TIMEOUT_S)
	var payload := {
		"model": NpcDecisionTuning.MODEL,
		"state": "Readiness check.",
		"questions": {
			"act": {
				"type": "choice",
				"instructions": "What should you do right now?",
				"criteria": { "ok": "report that you are ready" },
			},
		},
	}
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "http://%s:%d%s" % [
		NpcDecisionTuning.SERVER_HOST,
		port,
		NpcDecisionTuning.SERVER_PATH,
	]
	if _probe.request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload)) != OK:
		# The request couldn't even start (not expected for a fixed localhost URL); treat it as
		# a failed attempt so the retry/launch path still runs.
		_on_probe_completed(
			HTTPRequest.RESULT_CANT_CONNECT,
			0,
			PackedStringArray(),
			PackedByteArray(),
		)


## Only a 200 — a decision actually returned — counts as live. The other outcomes are distinct
## faults: a non-200 means a server IS bound but cannot decide (it could not load its weights, say),
## and launching our own would merely fail to bind the port, so we retry briefly in case it is still
## warming up and then report its own explanation. A REFUSED connection means nothing is bound, so
## we launch at once rather than spending the retry budget (those retries only pay off for an answer
## that TIMED OUT — a slow or just-orphaned server worth reusing). After launching we poll our own
## server until it decides or `ready_timeout` passes.
func _on_probe_completed(
	result: int,
	code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_announce_ready()
		return
	if _probe.waiting_ready and _server_exited():
		await _report_exit()  # The boot script ended: its setup is missing, or the port is held.
		return
	var out_of_time := Time.get_ticks_msec() >= _probe.ready_deadline_ms
	var retry := _probe.attempts_left > 0 and not out_of_time
	if result == HTTPRequest.RESULT_SUCCESS:
		if retry:
			await _wait_then_probe()
		else:
			_give_up(
				("[von] Server on port %d is up but cannot decide (HTTP %d): %s. If it is not Von, "
				+ "free the port; if it is an old Von, stop it (tools/von_stop.sh <game pid>, or "
				+ "end the process holding the port) and start the game again. NPCs hold steady.")
				% [port, code, _detail(body)],
			)
	elif _probe.waiting_ready:
		if out_of_time:
			_give_up(
				"[von] Server has not answered within %.0fs; NPCs hold steady until it does."
				% ready_timeout,
			)
		else:
			await _wait_then_probe()
	elif result == HTTPRequest.RESULT_CANT_CONNECT:
		_launch_and_await_ready()
	elif retry:
		await _wait_then_probe()
	else:
		# Something accepts connections on the port and never decides (a timeout, a connection that
		# is no HTTP): not a server of ours to replace, and a second one could not bind it.
		_give_up(
			("[von] Port %d is held by something that does not answer a decision, so it is not "
			+ "Von: free the port and start the game again. NPCs hold steady.") % port,
		)


## The server's own explanation for a non-200: `DecisionClient.error_detail`, capped at 300
## characters to keep the warning readable (an empty `detail` reads as an empty body too).
func _detail(body: PackedByteArray) -> String:
	if body.is_empty():
		return "(empty response body)"  # Not parsed: an empty text is a JSON error in the log.
	var text := DecisionClient.error_detail(body)
	if text == "":
		return "(empty response body)"
	return text if text.length() <= 300 else text.substr(0, 300) + "…"


## Whether something accepts a TCP connection on `port`: a server (ours, another's) is bound. A
## refused or unanswered connect within `CONNECT_WAIT_S` says nothing is, without the HTTP request's
## own timeout (a closed port can take that whole 15 s to give up on Windows).
func _port_open() -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host(NpcDecisionTuning.SERVER_HOST, port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + int(CONNECT_WAIT_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		match peer.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				peer.disconnect_from_host()
				return true
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				return false
		if not is_inside_tree():
			return false
		await get_tree().process_frame
	peer.disconnect_from_host()
	return false


## Wait out `probe_interval` and probe again, bailing if the node left the tree mid-wait (the game
## quit while we were polling). A boot script that ended meanwhile is reported at once.
func _wait_then_probe() -> void:
	await get_tree().create_timer(probe_interval).timeout
	if _probe.request == null:
		return
	if _probe.waiting_ready and _server_exited():
		await _report_exit()
		return
	_probe_once()


## Start our own server, then poll it until it answers so `resolved` fires `true` only for a LIVE
## brain rather than merely a spawned process. If nothing started (a probe-only launcher, a boot
## script that is missing or would not spawn) there is nothing to wait for, so probing stops.
func _launch_and_await_ready() -> void:
	_launch()
	if _pid <= 0:
		_resolve(false)  # Nothing started: nothing to wait for (`_launch` said why).
		return
	_probe.waiting_ready = true
	await _wait_then_probe()


## The server answered: report how long it took from scene load and let anyone gating on it proceed.
func _announce_ready() -> void:
	var secs: float = (Time.get_ticks_msec() - _start_ms) / 1000.0
	if _server_exited():
		# Ours stopped (the port was already taken) and what answers is another's: reuse it.
		_pid = -1
	if _pid > 0:
		GameLog.say("[von] Decision server live on port %d, %.1fs after scene load (pid %d)."
				% [port, secs, _pid])
		var args := qos_args(_pid, OS.get_name(), background_qos)
		if not args.is_empty():
			var line := qos_failure_line(OS.execute("/usr/sbin/taskpolicy", args))
			if not line.is_empty():
				GameLog.say(line)
	else:
		GameLog.say("[von] Reusing the decision server already running on port %d." % port)
	_resolve(true)


## Free the probe node once probing is done (reuse found, attempts exhausted, or on exit).
func _end_probing() -> void:
	if _probe.request != null:
		_probe.request.queue_free()
		_probe.request = null


## The arguments for `/usr/sbin/taskpolicy` that move the running server `pid` to background QoS
## (`-b -p <pid>`); empty when it does not apply: not macOS, `background` off, or no server of ours.
static func qos_args(pid: int, os_name: String, background: bool) -> PackedStringArray:
	if not background or os_name != "macOS" or pid <= 0:
		return PackedStringArray()
	return PackedStringArray(["-b", "-p", str(pid)])


## The log line for a `taskpolicy` run that ended with `exit_code`: empty on 0, otherwise the line
## that says the QoS was not applied (70 is a dead pid, -1 a `taskpolicy` that could not start).
static func qos_failure_line(exit_code: int) -> String:
	if exit_code == 0:
		return ""
	return "[von] QoS not applied (exit %d)." % exit_code


## Whether the boot script we started has ended (the setup is missing, or the server stopped).
func _server_exited() -> bool:
	return _pid > 0 and not OS.is_process_running(_pid)


## The boot script ended before the server answered: say why (its own `von: <cause>. Fix: <command>`
## line, else the last lines it printed) and settle with no server. It gives the readers a moment to
## drain the pipes first, so the line has been read.
func _report_exit() -> void:
	var code := OS.get_process_exit_code(_pid)
	var waited := 0.0
	while waited < 2.0 and _output.alive():
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
		if _resolved or not is_inside_tree():
			return
	_pid = -1
	_give_up(exit_warning(code, _output.von_line(), _output.tail(), port))


## Warn, remember why (`problem`) and settle with no server.
func _give_up(text: String) -> void:
	push_warning(text)
	problem = text
	_resolve(false)


## The program and arguments that run the boot script of `os_name` start-only, with the project
## folder `project_dir` (globalized, no trailing slash): Windows PowerShell 5.1 with
## `-ExecutionPolicy Bypass` (the scripts dot-source lib.ps1), anything else the bash script, which
## becomes the server. `system_root` is `%SystemRoot%` (empty: found on `PATH`).
static func boot_command(
	os_name: String,
	project_dir: String,
	server_port: int,
	server_device: String,
	system_root := "",
) -> Dictionary:
	if os_name == "Windows":
		var powershell := "powershell.exe"
		if system_root != "":
			powershell = system_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
		return {
			"program": powershell,
			"script": project_dir.path_join("tools/von/boot.ps1"),
			"args": PackedStringArray([
				"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
				"-File", project_dir.path_join("tools/von/boot.ps1"),
				"-Port", str(server_port),
				"-BindHost", NpcDecisionTuning.SERVER_HOST,
				"-Device", server_device,
			]),
		}
	return {
		"program": project_dir.path_join("tools/von/boot.sh"),
		"script": project_dir.path_join("tools/von/boot.sh"),
		"args": PackedStringArray([
			"--host", NpcDecisionTuning.SERVER_HOST,
			"--port", str(server_port),
			"--device", server_device,
		]),
	}


## The warning for a boot script that ended before any server answered, with its exit `code`: the
## script's own `von:` line when it printed one (exit 3: no venv, no Python, no weights ... and the
## bootstrap command that fixes it), else the last lines it printed, which name a port in use.
static func exit_warning(
	code: int,
	von_line: String,
	tail: PackedStringArray,
	server_port: int,
) -> String:
	if von_line != "":
		return "[von] No decision server: %s. NPCs hold steady." % von_line.trim_suffix(".")
	var said := " ".join(tail) if not tail.is_empty() else "(it printed nothing)"
	return (
		("[von] The decision server stopped right after starting (exit %d): %s. Is port %d held by "
		+ "another program? See user://von_server.log. NPCs hold steady.")
		% [code, said, server_port]
	)


## Run the boot script with its output piped back to us, and a thread per pipe to read it.
func _launch() -> void:
	if probe_only:
		GameLog.say("[von] No server on port %d, and this launcher only probes." % port)
		return
	var command := boot_command(
		OS.get_name(),
		ProjectSettings.globalize_path("res://").trim_suffix("/"),
		port,
		device,
		OS.get_environment("SystemRoot"),
	)
	if not FileAccess.file_exists(command["script"]):
		_give_up("[von] No decision server: %s is missing. NPCs hold steady." % command["script"])
		return
	var process := OS.execute_with_pipe(command["program"], command["args"])
	if process.is_empty():
		_give_up(
			"[von] No decision server: could not run %s. NPCs hold steady." % command["program"],
		)
		return
	_pid = process["pid"]
	_output.echo = echo_to_output
	_output.start(process, LOG_PATH)
	GameLog.say("[von] Started decision server (pid %d); log: %s"
			% [_pid, ProjectSettings.globalize_path(LOG_PATH)])
