@tool
extends Node
## The coverage tool's probe (tools/coverage/README.md). This file is a template that is never
## registered in the game: instrument.py copies it into an instrumented copy of the repo as
## tools/coverage/coverage_probe.gd, with COUNT and MAP_HASH filled in, and registers it as the
## first autoload, CoverageProbe. Every statement of the copy's scenes/**/*.gd bumps its own counter
## in `h` (`CoverageProbe.h[7] += 1; <statement>`).
##
## Without FE_COVERAGE it only holds the counters, so the copy loads and runs like the game (the
## load check, the lint and the game tests run on it). With FE_COVERAGE naming a run's config (a
## JSON file runner.py writes: `source`, `hits_dir`, `flush`, and for matches `seed`, `mode`,
## `matches`, `defenders`, `invaders`), it writes this process's hits to
## <hits_dir>/coverage_hits_<pid>.json (the hit file format) every `flush` seconds of real time and
## at exit (the last flush, as the tree is freed after every node's _exit_tree, marks the file
## `final`), kept apart in units:
##   matches  one unit per match. It starts each match itself, by emitting the setup window's
##            start_requested(config), ends the unit at the MatchHUD's match_ended(verdict), and
##            caps a match that runs CAP_GRACE game seconds past Main's endless_time_limit. A match
##            is timed from its world: the node Main adds to the group `match_world` when it builds
##            the match (the frame the MatchHUD's clock starts), so the wait before it (the Von
##            server, the pause between Endless matches) is in no duration and the cap counts the
##            match itself; a match that ends before its world appeared fails the process. The hits
##            before the first match (start-up) count in the first, those after a match ends in the
##            next; the process quits after its last match. Each match also records its outcome and
##            its cost, to compare an instrumented run with an uninstrumented one, all from its
##            world on: `shots` (the EventBus autoload's `shot` posts; null without an EventBus),
##            `deaths` (the nodes of the group `characters` whose `is_dead` is true when it ends;
##            null when the group is empty), `wall` (real seconds), `frames` (process frames),
##            `physics_peak_ms` and `process_peak_ms` (the engine's TIME_PHYSICS_PROCESS and
##            TIME_PROCESS monitors averaged over its physics and process frames; each monitor holds
##            the slowest frame of the second before, so these are the typical worst step of a
##            second, not the mean step), and how often its NPCs got a Von decision (`npcs`,
##            `decisions`, `decided`, `failed`, `decided_per_npc_minute`, `von_failed_share`:
##            _von_rate).
##   tests    one unit per test. The tests run in game test suites
##            (scenes/testing/game_test_suite.gd), each a node of the group RUNNER_GROUP while it
##            runs, one after another; the probe follows the newest to join the tree. A unit is
##            keyed by the id of the suite's current entry (`open_entry`) while the test's context
##            (the suite's `open_ctx`, a TestContext) is live and not `is_finished`, looked at every
##            frame and whenever a node is added. The probe ends the test's unit when the context
##            emits `finished` (the test's verdict), before the suite hears it, so the suite's
##            teardown after it is not the test's. The hits made while no test runs (the start-up,
##            each test's teardown, the start of the next test until its context is open) go to an
##            `outside` unit (`{ "id": "", "outside": true }`), so code that ran is never read as
##            never run, and no test is charged with it. A test that ends before the probe sees its
##            context open (a skip, a script error) has no unit. This process's file may hold
##            several units of one id: an `outside` unit for each stretch between tests, and a unit
##            for each run of a repeated test; the merge sums units that share an id, so the run's
##            hits.json holds one per test and one `outside`. A process in which no suite ever
##            joined the group fails as it exits.
## A hook it needs that is missing fails the process loudly: an error in the log,
## coverage_failed_<pid>.txt beside the hits, exit code 3.

const COUNT := 0
const MAP_HASH := ""
const FORMAT := "fe-coverage-hits"
const VERSION := 1
## Game seconds past Main's endless_time_limit before the probe ends a match itself (the MatchHUD
## calls an Endless match a draw at the limit; a Watch match has no limit of its own).
const CAP_GRACE := 0.25
const CAP_VERDICT := "TIME CAP"
const FAILED_EXIT := 3
## tests: the group the game's test suites join (scenes/testing/game_test_suite.gd GROUP).
const RUNNER_GROUP := &"game_test_suites"

## The counters, one per statement id of the map. Read element by element only: a copy of the array
## would be copied again on the next bump.
var h := PackedInt32Array()
## the run config FE_COVERAGE names ({} = idle)
var _config: Dictionary = {}
## the config's `source`: "matches" or "tests" ("" = idle)
var _source := ""
## "" = write nothing (idle, or failed)
var _hits_path := ""
## real milliseconds between flushes (the config's `flush`)
var _flush_ms := 5000
## Time.get_ticks_msec() of the next flush
var _next_flush := 0
## `h` as of the last collect
var _base := PackedInt32Array()
## the closed units, as JSON
var _closed := PackedStringArray()
## the open unit without its counts ({} = none: hits are dropped)
var _unit: Dictionary = {}
## the open unit's counts: statement id -> hits
var _counts: Dictionary = {}
## matches: how many this process plays
var _planned := 1
## matches: the open match's number, from 1
var _match := 0
## matches: the open match's world has appeared, so its clock runs
var _started := false
## matches: physics frames since the open match's world appeared
var _frames := 0
## matches: Main's endless_time_limit
var _limit := 0.0
## matches: the last match is decided; the process is quitting
var _ending := false
## the tree is being freed: the flush now is the last one
var _final := false
## matches: the EventBus autoload (null = the game has none: shots not counted)
var _bus: Node
## matches: `shot` posts since the open match started
var _shots := 0
## matches: decision planners' `decided` signals since the open match started
var _decided := 0
## matches: decision planners' `failed` signals since the open match started
var _undecided := 0
## matches: Time.get_ticks_usec() when the open match's world appeared
var _wall_start := 0
## matches: Engine.get_process_frames() when the open match's world appeared
var _frame_start := 0
## matches: TIME_PHYSICS_PROCESS summed over the open match's physics frames
var _physics_sum := 0.0
## matches: the physics frames in _physics_sum
var _physics_n := 0
## matches: TIME_PROCESS summed over the open match's process frames
var _process_sum := 0.0
## matches: the process frames in _process_sum
var _process_n := 0
## tests: the game test suite running now (null between suites)
var _runner: Node
## tests: a suite has joined the group in this process
var _found_runner := false
## tests: the id of the test the open unit belongs to
var _test_id := ""


func _init() -> void:
	h.resize(COUNT)


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if Engine.is_editor_hint():
		return
	var path := OS.get_environment("FE_COVERAGE")
	if path == "":
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("FE_COVERAGE names no readable run config: %s" % path)
		return
	_config = parsed
	_source = str(_config.get("source", ""))
	_hits_path = str(_config.get("hits_dir", ".")).path_join("coverage_hits_%d.json"
			% OS.get_process_id())
	_flush_ms = int(float(_config.get("flush", 5.0)) * 1000.0)
	_next_flush = Time.get_ticks_msec() + _flush_ms
	_base.resize(COUNT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_physics_process(true)
	if _source == "matches":
		_start_matches.call_deferred()
	elif _source == "tests":
		_find_runner.call_deferred()
	else:
		_fail("unknown source in the run config: %s" % _source)


func _process(_delta: float) -> void:
	if _runner != null:
		_check_test()
	if _source == "matches" and _started and not _ending:
		_process_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		_process_n += 1
	if Time.get_ticks_msec() >= _next_flush:
		_flush()


func _physics_process(_delta: float) -> void:
	if _source != "matches" or not _started or _ending:
		return
	_frames += 1
	_physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_physics_n += 1
	if _frames >= (_limit + CAP_GRACE) * Engine.physics_ticks_per_second:
		_end_match(CAP_VERDICT, true)


func _exit_tree() -> void:
	if _source == "tests" and _hits_path != "" and not _found_runner:
		_fail("no node of the group %s (a game test suite) appeared, so no test could be told apart"
				% RUNNER_GROUP)
	_flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_final = true
		_flush()  # after every node's _exit_tree


# --- Matches --------------------------------------------------------------------------------------


## Find Main's hooks, then start the first match.
func _start_matches() -> void:
	await get_tree().process_frame  # the main scene's _ready has run
	var main := get_tree().current_scene
	if main == null or not ("endless_time_limit" in main):
		_fail(
			"the main scene has no endless_time_limit (Main's export; a parse error in Main's"
			+ " script leaves it out: see the game log), so no match can be capped",
		)
		return
	var menu := _find_with_signal(main, &"start_requested")
	if menu == null:
		_fail("the setup window's start_requested signal was not found under the main scene")
		return
	var hud := _find_with_signal(main, &"match_ended")
	if hud == null:
		_fail("the MatchHUD's match_ended signal was not found under the main scene")
		return
	hud.connect(&"match_ended", _on_match_ended)
	_bus = get_tree().root.get_node_or_null(^"EventBus")
	if _bus != null and _bus.has_signal(&"posted"):
		_bus.connect(&"posted", _on_posted)
	else:
		_bus = null
	_limit = float(main.get("endless_time_limit"))
	_planned = maxi(1, int(_config.get("matches", 1)))
	get_tree().node_added.connect(_on_match_node_added)
	_open_match()
	menu.emit_signal(
		&"start_requested",
		{
			"mode": str(_config.get("mode", "watch")), "seed": int(_config.get("seed", 0)),
			"lead": false, "defenders": { "count": int(_config.get("defenders", 1)) },
			"invaders": { "count": int(_config.get("invaders", 1)) },
		},
	)


## Open the next match's unit; its clock waits for the match's world (_on_match_node_added).
func _open_match() -> void:
	_match += 1
	_frames = 0
	var seed_value := int(_config.get("seed", 0))
	_unit = {
		"id": "%d-%d" % [seed_value, _match], "seed": seed_value,
		"mode": str(_config.get("mode", "watch")), "match": _match, "verdict": "", "duration": 0.0,
	}
	_counts = {}
	_started = false


## The open match's world joined the tree: its clock, its outcome and its cost start now.
func _on_match_node_added(node: Node) -> void:
	if node.has_signal(&"decided") and node.has_signal(&"failed"):
		node.connect(&"decided", _on_decided)
		node.connect(&"failed", _on_undecided)
	if _started or _ending or _unit.is_empty() or not node.is_in_group(&"match_world"):
		return
	_started = true
	_frames = 0
	_shots = 0
	_decided = 0
	_undecided = 0
	_wall_start = Time.get_ticks_usec()
	_frame_start = Engine.get_process_frames()
	_physics_sum = 0.0
	_physics_n = 0
	_process_sum = 0.0
	_process_n = 0


## A decision planner (a node with the signals `decided(leaf)` and `failed()`) ended a walk with
## Von's answer.
func _on_decided(_leaf: Dictionary) -> void:
	if _started and not _ending:
		_decided += 1


## A decision planner ended a walk without an answer (Von timed out or gave a bad pick: the NPC
## holds steady).
func _on_undecided() -> void:
	if _started and not _ending:
		_undecided += 1


## An EventBus post: a `shot` counts toward the open match's shots.
func _on_posted(topic: StringName, _data: Dictionary) -> void:
	if topic == &"shot" and _started and not _ending:
		_shots += 1


## The MatchHUD decided the open match.
func _on_match_ended(verdict: String) -> void:
	if not _unit.is_empty() and not _ending:
		_end_match(verdict, false)


## Decide the open match. The next one opens at once (its unit holds the teardown and the pause
## before it); after the last one, or a capped one, the process quits and the hits until then stay
## with this match.
func _end_match(verdict: String, capped: bool) -> void:
	if not _started:
		_fail(("match %d ended (%s) before any node of the group match_world appeared: the world "
					+ "Main builds a " + "match in, which a match is timed from, was not found")
				% [_match, verdict])
		return
	_collect()
	_unit["verdict"] = verdict
	_unit["duration"] = float(_frames) / Engine.physics_ticks_per_second
	_unit["shots"] = null
	if _bus != null:
		_unit["shots"] = _shots
	_unit["deaths"] = _deaths()
	_unit["wall"] = (Time.get_ticks_usec() - _wall_start) / 1_000_000.0
	_unit["frames"] = Engine.get_process_frames() - _frame_start
	_unit["physics_peak_ms"] = _physics_sum * 1000.0 / maxi(1, _physics_n)
	_unit["process_peak_ms"] = _process_sum * 1000.0 / maxi(1, _process_n)
	_unit.merge(_von_rate(_unit["duration"]), true)
	if _match < _planned and not capped:
		_close_unit()
		_open_match()
		return
	_ending = true
	_quit.call_deferred()


## The characters dead as the match ends (null when no node is in the group `characters`).
func _deaths() -> Variant:
	var characters := get_tree().get_nodes_in_group(&"characters")
	if characters.is_empty():
		return null
	var dead := 0
	for c in characters:
		if c.get("is_dead") == true:
			dead += 1
	return dead


## How often the match's NPCs got a Von decision: `npcs` (the AI controllers, the group
## `npc_controllers`, as it ends), `decisions` (their debug_state() `decisions`, the walks started,
## summed), `decided` and `failed` (the walks the decision planners ended with Von's answer and
## without one, counted from their signals during the match), `decided_per_npc_minute` (decided per
## NPC per game minute) and `von_failed_share` (failed / (decided + failed); null when no walk
## ended). A starved Von server times its walks out: walks keep starting at the decide cadence while
## few are decided, so the decided rate is the one a starved match shows in. With no controller, all
## but `npcs` are null.
func _von_rate(duration: float) -> Dictionary:
	var controllers := get_tree().get_nodes_in_group(&"npc_controllers")
	var out := { "npcs": controllers.size(), "decisions": null, "decided": null, "failed": null,
		"decided_per_npc_minute": null, "von_failed_share": null }
	if controllers.is_empty():
		return out
	var decisions := 0
	for c in controllers:
		var state: Dictionary = c.debug_state()
		decisions += int(state.get("decisions", 0))
	out["decisions"] = decisions
	out["decided"] = _decided
	out["failed"] = _undecided
	out["decided_per_npc_minute"] = (_decided / float(controllers.size())
			/ maxf(duration / 60.0, 1.0 / 3600.0))
	if _decided + _undecided > 0:
		out["von_failed_share"] = _undecided / float(_decided + _undecided)
	return out


## Flush, then quit the game (after the last match).
func _quit() -> void:
	_flush()
	get_tree().quit()


## The first node under `root` (breadth first, `root` included) with the signal `signal_name`, or
## null.
func _find_with_signal(root: Node, signal_name: StringName) -> Node:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node.has_signal(signal_name):
			return node
		queue.append_array(node.get_children())
	return null


# --- Tests ----------------------------------------------------------------------------------------


## Watch for the game test suites: each joins RUNNER_GROUP as gdUnit adds it to the tree, and its
## tests open and end while it is there. Called deferred from _ready, so it is listening before the
## first suite is added.
func _find_runner() -> void:
	_unit = _outside_unit()  # the start-up so far, until the first test
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group(RUNNER_GROUP):
		_adopt(node)
	_check_test()


## A node joined the tree: a suite that starts its tests now, or a node of the open suite's test (it
## adds the test's world once its context is open).
func _on_node_added(node: Node) -> void:
	if node != _runner and node.is_in_group(RUNNER_GROUP):
		_adopt(node)
	_check_test()


## Follow the suite `node` from now on, once it is seen to have the hooks (`open_entry`,
## `open_ctx`).
func _adopt(node: Node) -> void:
	if not ("open_entry" in node):
		_fail("the game test suite's current entry (open_entry on %s) was not found" % node.name)
		return
	if not ("open_ctx" in node):
		_fail("the game test suite's test context (open_ctx on %s) was not found" % node.name)
		return
	_runner = node
	_found_runner = true


## The open test's context emitted `finished`: the test is decided, so its unit ends here.
func _on_test_finished() -> void:
	_check_test()


## When the test running changed (one opened, or the open one finished), the hits so far belong to
## the unit before.
func _check_test() -> void:
	if not is_instance_valid(_runner):
		return
	var ctx: Variant = _runner.get("open_ctx")
	var live := is_instance_valid(ctx)
	if live and not ("is_finished" in ctx and ctx.has_signal(&"finished")):
		_runner = null
		_fail(
			"the game test suite's test context (open_ctx) has no is_finished"
			+ " or no finished signal",
		)
		return
	var entry: Variant = _runner.get("open_entry")
	var running: bool = live and ctx.get("is_finished") == false and entry is Dictionary
	var id := str(entry.get("id", "")) if running else ""
	if id == _test_id:
		return
	_collect()
	_close_unit()
	_test_id = id
	_unit = { "id": id } if id != "" else _outside_unit()
	if id != "":
		_listen_for_end(ctx)


## Hear the open test's end first: a listener connected before the probe would run before it, and
## what it runs then (the runner's teardown) would be charged to the test.
func _listen_for_end(ctx: Object) -> void:
	if not ctx.get_signal_connection_list(&"finished").is_empty():
		_runner = null
		_fail(("something listens to test %s's finished before the probe could (the suite should "
					+ "add the test's "
				+ "world before it waits for the end): its teardown would be charged to the test")
				% _test_id)
		return
	ctx.connect(&"finished", _on_test_finished, CONNECT_ONE_SHOT)


## The unit of the hits made while no test runs.
func _outside_unit() -> Dictionary:
	return { "id": "", "outside": true }


# --- Hits -----------------------------------------------------------------------------------------


## Move the hits since the last collect into the open unit (dropped when none is open).
func _collect() -> void:
	var keep := not _unit.is_empty()
	for i in COUNT:
		var now := h[i]
		var was := _base[i]
		if now != was:
			_base[i] = now
			if keep:
				_counts[i] = int(_counts.get(i, 0)) + now - was


## Keep the open unit, as JSON, with the closed ones; none is open after.
func _close_unit() -> void:
	if not _unit.is_empty():
		_closed.append(_unit_json())
	_unit = {}
	_counts = {}


## The open unit with its counts, as one JSON object (statement ids as string keys).
func _unit_json() -> String:
	var unit := _unit.duplicate()
	var counts := {}
	for id: int in _counts:
		counts[str(id)] = _counts[id]
	unit["counts"] = counts
	return JSON.stringify(unit)


## Write the hit file: a temp file renamed over the old one, so a reader (or a kill -9) never leaves
## half a file.
func _flush() -> void:
	_next_flush = Time.get_ticks_msec() + _flush_ms
	if _hits_path == "":
		return
	_collect()
	var units := _closed.duplicate()
	if not _unit.is_empty():
		units.append(_unit_json())
	var text := (('{"format": "%s", "version": %d, "map_hash": "%s", "source": "%s", "final": %s, '
			+ '"units": [\n%s\n]}\n')
			% [
				FORMAT,
				VERSION,
				MAP_HASH,
				_source,
				"true" if _final else "false",
				",\n".join(units),
			])
	var tmp := _hits_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("coverage probe: cannot write %s (%s)"
				% [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(tmp, _hits_path)
	if err != OK:
		push_error("coverage probe: cannot rename %s over %s (%s)"
				% [tmp, _hits_path, error_string(err)])


## A hook the probe needs is missing: log it, write coverage_failed_<pid>.txt beside the hits, stop
## writing hits and quit with FAILED_EXIT.
func _fail(message: String) -> void:
	var text := "coverage probe: " + message
	push_error(text)
	printerr(text)
	var dir := str(_config.get("hits_dir", ""))
	if dir != "":
		var f := FileAccess.open(
			dir.path_join("coverage_failed_%d.txt" % OS.get_process_id()),
			FileAccess.WRITE,
		)
		if f != null:
			f.store_line(text)
	_hits_path = ""
	get_tree().quit(FAILED_EXIT)
