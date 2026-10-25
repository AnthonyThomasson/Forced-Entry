extends SceneTree
## Helper of tools/test_gdunit_panel.py: runs tests the way the editor's GdUnit panel does, without
## an editor. What the panel's Run (GdUnitCommandHandler.gd: `cmd_run_overall` and
## `run_release_mode`) does, in order:
## - discovers the cases (`GdUnitTestDiscoverer.run`, as "Run overall"), keeping those of the
##   catalog ids given (the process takes no `--` options, as the editor has none: the suites read
##   them, test_batch.gd, and would list a selection instead of every case);
## - starts gdUnit's TCP server (`GdUnitTcpServer`, the editor's end of the runner's reports);
## - saves the run config (`GdUnitRunnerConfig`: the cases and the server's port, to
##   res://addons/gdUnit4/GdUnitRunner.cfg);
## - starts the runner with the arguments the panel gives it: `--no-window --path <project>
##   res://addons/gdUnit4/src/core/runners/GdUnitTestRunner.tscn` (no `--fixed-fps`, no `--`
##   options), plus `--headless` first when asked;
## - takes its events over the server until it closes the session, then stops the runner as the
##   editor does (`cmd_stop`: the editor's runner never quits by itself).
## "Run overall" starts the same runner scene through the editor's Play (debug mode, the editor's
## debugger attached), Run on a case in release mode, as here; either way without `--fixed-fps`.
## It prints `RUNNER <pid> <args>`, then a `CASE {json}` line per case that ended (`id`, `name`,
## `status`: passed / failed / skipped, `message`: the reports' text), then `DONE <cases> <end>`
## (`end`: `stopped` when the runner closed its session and was stopped, `exited` when it quit
## before that, `timeout` when its session was still open after the timeout and it was killed).
## Run it on a scratch copy of the checkout: the run config lands in the project. Its options go by
## environment:
##   GDUNIT_PANEL_IDS=a,b [GDUNIT_PANEL_HEADLESS=1] [GDUNIT_PANEL_TIMEOUT=600] \
##       godot --headless --path <copy> -s res://tools/gdunit_panel.gd

const GdUnitTools := preload("res://addons/gdUnit4/src/core/GdUnitTools.gd")
const RUNNER_SCENE := "res://addons/gdUnit4/src/core/runners/GdUnitTestRunner.tscn"
## A test id in a wrapper suite's case name: `test_ui:3 ('ui/inspector_outfit')`.
const CASE_ID := "\\('([^']+)'\\)$"
## The first port tried, away from the editor's own (31002): a panel open on the checkout this was
## copied from may be listening there.
const FIRST_PORT := 32_702
## How long (ms) a closed session's runner has to hang up before it is stopped.
const HANG_UP_MS := 2000

## gdUnit's TCP server, the editor's end of the runner's reports.
var _server: GdUnitTcpServer
## str(guid) -> [id, display name] of each case run.
var _cases := {}
## How many cases the runner has reported ended.
var _ended := 0
## Time (msec) the runner reported its session closed; -1 while it is open.
var _closed_at := -1


func _initialize() -> void:
	_run.call_deferred()


## Does the panel's Run on the cases of `GDUNIT_PANEL_IDS`, prints what ended, and quits.
func _run() -> void:
	var ids := OS.get_environment("GDUNIT_PANEL_IDS").split(",", false)
	var timeout := 600.0
	if OS.has_environment("GDUNIT_PANEL_TIMEOUT"):
		timeout = float(OS.get_environment("GDUNIT_PANEL_TIMEOUT"))
	var picked := await _pick(ids)
	_server = GdUnitTcpServer.new()
	root.add_child(_server)
	var started := _server.start(FIRST_PORT)
	if started.is_error():
		push_error(started.error_message())
		quit(1)
		return
	_server.rpc_data.connect(_on_rpc)
	var saved := GdUnitRunnerConfig.new().clear().add_test_cases(picked).set_server_port(
		started.value(),
	).save_config()
	if saved.is_error():
		push_error(saved.error_message())
		quit(1)
		return
	var end := await _await_runner(_start_runner(), timeout)
	# The last events may still be in the socket when the runner has quit.
	for i in 30:
		await process_frame
	print("DONE %d %s" % [_ended, end])
	_server.stop()
	_server.queue_free()
	picked.clear()
	# What gdUnit's own command-line runner does before it quits: its singletons outlive the tree
	# otherwise, and the engine crashes freeing them at exit.
	GdUnitTools.dispose_all()
	await GdUnitMemoryObserver.gc_on_guarded_instances()
	quit()


## The discovered cases of the catalog ids `ids` (each kept in `_cases` by its guid), as "Run
## overall" discovers them.
func _pick(ids: PackedStringArray) -> Array[GdUnitTestCase]:
	var picked: Array[GdUnitTestCase] = []
	var id_of := RegEx.create_from_string(CASE_ID)
	for c: GdUnitTestCase in await GdUnitTestDiscoverer.run():
		var found := id_of.search(c.display_name)
		if found != null and found.get_string(1) in ids:
			picked.append(c)
			_cases[str(c.guid)] = [found.get_string(1), c.display_name]
	return picked


## Starts the runner with the panel's arguments (`--headless` first when asked) and prints its
## `RUNNER` line; returns its pid.
func _start_runner() -> int:
	var args: Array[String] = []
	if OS.get_environment("GDUNIT_PANEL_HEADLESS") == "1":
		args.append("--headless")
	args.append_array(
		["--no-window", "--path", ProjectSettings.globalize_path("res://"), RUNNER_SCENE],
	)
	var pid := OS.create_process(OS.get_executable_path(), args)
	print("RUNNER %d %s" % [pid, " ".join(args)])
	return pid


## Waits for the runner `pid` to quit, to hang up `HANG_UP_MS` after its session closed, or for
## `timeout` s, killing it if it still runs; returns how it ended: `exited`, `stopped`, `timeout`.
func _await_runner(pid: int, timeout: float) -> String:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		if _closed_at >= 0 and Time.get_ticks_msec() > _closed_at + HANG_UP_MS:
			break
		await process_frame
	var end := "exited"
	if OS.is_process_running(pid):
		end = "stopped" if _closed_at >= 0 else "timeout"
		OS.kill(pid)
	return end


## A report from the runner: print each case that ended.
func _on_rpc(data: RPC) -> void:
	if not data is RPCGdUnitEvent:
		return
	var event: GdUnitEvent = (data as RPCGdUnitEvent).event()
	if event.type() == GdUnitEvent.SESSION_CLOSE:
		_closed_at = Time.get_ticks_msec()
	if event.type() != GdUnitEvent.TESTCASE_AFTER:
		return
	var known: Array = _cases.get(str(event.guid()), ["", ""])
	var status := "passed"
	if event.is_skipped():
		status = "skipped"
	elif event.is_failed() or event.is_error():
		status = "failed"
	var text: Array = event.reports().map(func(r: GdUnitReport) -> String: return r.message())
	_ended += 1
	print("CASE " + JSON.stringify({
		"id": known[0], "name": known[1], "status": status, "message": "\n".join(text),
	}))
