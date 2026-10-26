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
##            caps a match that runs Matches.CAP_GRACE game seconds past Main's
##            endless_time_limit. A match is timed from its world: the node Main adds to the group
##            `match_world` when it builds the match (the frame the MatchHUD's clock starts), so the
##            wait before it (the Von server, the pause between Endless matches) is in no duration
##            and the cap counts the match itself; a match that ends before its world appeared fails
##            the process. The hits before the first match (start-up) count in the first, those
##            after a match ends in the next; the process quits after its last match. Each match
##            also records its outcome and its cost, to compare an instrumented run with an
##            uninstrumented one, all from its world on: `shots` (the EventBus autoload's `shot`
##            posts; null without an EventBus), `deaths` (the nodes of the group `characters` whose
##            `is_dead` is true when it ends; null when the group is empty), `wall` (real seconds),
##            `frames` (process frames),
##            `physics_peak_ms` and `process_peak_ms` (the engine's TIME_PHYSICS_PROCESS and
##            TIME_PROCESS monitors averaged over its physics and process frames; each monitor holds
##            the slowest frame of the second before, so these are the typical worst step of a
##            second, not the mean step), and how often its NPCs got a Von decision (`npcs`,
##            `decisions`, `decided`, `failed`, `decided_per_npc_minute`, `von_failed_share`:
##            Matches._von_rate).
##   tests    one unit per test. The tests run in game test suites
##            (scenes/testing/game_test_suite.gd), each a node of the group Tests.RUNNER_GROUP while
##            it runs, one after another; the probe follows the newest to join the tree. A unit is
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
##
## The run config is read into `run` (a Run), and the units of its source are kept by a part, built
## in _ready for that source only: Matches (with its MatchCost) or Tests. All four are inner
## classes, since instrument.py copies only this file into the copy (and a project with no
## tools/coverage/, such as the tool's test fixture, could load no other file of it). Matches and
## Tests hold the probe; Run and MatchCost hold nothing of it.

const COUNT := 0
const MAP_HASH := ""
const FORMAT := "fe-coverage-hits"
const VERSION := 1
const FAILED_EXIT := 3

## The counters, one per statement id of the map. Read element by element only: a copy of the array
## would be copied again on the next bump.
var h := PackedInt32Array()
## the run config FE_COVERAGE names (null = idle)
var run: Run
## "" = write nothing (idle, or failed)
var _hits_path := ""
## Time.get_ticks_msec() of the next flush
var _next_flush := 0
## `h` as of the last collect
var _base := PackedInt32Array()
## the closed units, as JSON
var _closed := PackedStringArray()
## the open unit without its counts ({} = none: hits are dropped)
var unit: Dictionary = {}
## the open unit's counts: statement id -> hits
var _counts: Dictionary = {}
## the tree is being freed: the flush now is the last one
var _final := false
## matches: the match units (null unless the source is "matches")
var _matches: Matches
## tests: the test units (null unless the source is "tests")
var _tests: Tests


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
	run = Run.parse(FileAccess.get_file_as_string(path))
	if run == null:
		fail("FE_COVERAGE names no readable run config: %s" % path)
		return
	_hits_path = (run.hits_dir if run.hits_dir != "" else ".").path_join("coverage_hits_%d.json"
			% OS.get_process_id())
	_next_flush = Time.get_ticks_msec() + run.flush_ms
	_base.resize(COUNT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_physics_process(true)
	if run.source == "matches":
		_matches = Matches.new(self, run)
		_matches.start.call_deferred()
	elif run.source == "tests":
		_tests = Tests.new(self)
		_tests.start.call_deferred()
	else:
		fail("unknown source in the run config: %s" % run.source)


func _process(_delta: float) -> void:
	if _tests != null:
		_tests.check()
	if _matches != null:
		_matches.process_frame()
	if Time.get_ticks_msec() >= _next_flush:
		flush()


func _physics_process(_delta: float) -> void:
	if _matches != null:
		_matches.physics_frame()


func _exit_tree() -> void:
	if _tests != null and _hits_path != "" and not _tests.found_runner:
		fail("no node of the group %s (a game test suite) appeared, so no test could be told apart"
				% Tests.RUNNER_GROUP)
	flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_final = true
		flush()  # after every node's _exit_tree


# --- Hits -----------------------------------------------------------------------------------------


## Open `next` as the unit the hits go to (its counts start empty).
func open_unit(next: Dictionary) -> void:
	unit = next
	_counts = {}


## Move the hits since the last collect into the open unit (dropped when none is open).
func collect() -> void:
	var keep := not unit.is_empty()
	for i in COUNT:
		var now := h[i]
		var was := _base[i]
		if now != was:
			_base[i] = now
			if keep:
				_counts[i] = int(_counts.get(i, 0)) + now - was


## Keep the open unit, as JSON, with the closed ones; none is open after.
func close_unit() -> void:
	if not unit.is_empty():
		_closed.append(_unit_json())
	unit = {}
	_counts = {}


## The open unit with its counts, as one JSON object (statement ids as string keys).
func _unit_json() -> String:
	var out := unit.duplicate()
	var counts := {}
	for id: int in _counts:
		counts[str(id)] = _counts[id]
	out["counts"] = counts
	return JSON.stringify(out)


## Write the hit file: a temp file renamed over the old one, so a reader (or a kill -9) never leaves
## half a file. Idle (no run), there is nothing to write.
func flush() -> void:
	if run == null:
		return
	_next_flush = Time.get_ticks_msec() + run.flush_ms
	if _hits_path == "":
		return
	collect()
	var units := _closed.duplicate()
	if not unit.is_empty():
		units.append(_unit_json())
	var text := (('{"format": "%s", "version": %d, "map_hash": "%s", "source": "%s", "final": %s, '
			+ '"units": [\n%s\n]}\n')
			% [
				FORMAT,
				VERSION,
				MAP_HASH,
				run.source,
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
func fail(message: String) -> void:
	var text := "coverage probe: " + message
	push_error(text)
	printerr(text)
	var dir := run.hits_dir if run != null else ""
	if dir != "":
		var f := FileAccess.open(
			dir.path_join("coverage_failed_%d.txt" % OS.get_process_id()),
			FileAccess.WRITE,
		)
		if f != null:
			f.store_line(text)
	_hits_path = ""
	get_tree().quit(FAILED_EXIT)


## The run config FE_COVERAGE names (a JSON file runner.py writes), each key typed with its default.
class Run:
	## "matches" or "tests"
	var source := ""
	## where the hit file and a failure file go ("" = not given: the hit file goes to ".", a failure
	## file nowhere)
	var hits_dir := ""
	## real milliseconds between flushes (the config's `flush`, in seconds)
	var flush_ms := 5000
	## matches: the seed its matches start with (the config's `seed`)
	var seed_value := 0
	## matches: "watch" or "endless"
	var mode := "watch"
	## matches: how many this process plays (at least 1)
	var matches := 1
	## matches: each side's size
	var defenders := 1
	var invaders := 1

	## The run config in JSON `text`, or null when it is not a JSON object.
	static func parse(text: String) -> Run:
		var parsed: Variant = JSON.parse_string(text)
		if not parsed is Dictionary:
			return null
		var config: Dictionary = parsed
		var out := Run.new()
		out.source = str(config.get("source", ""))
		out.hits_dir = str(config.get("hits_dir", ""))
		out.flush_ms = int(float(config.get("flush", 5.0)) * 1000.0)
		out.seed_value = int(config.get("seed", 0))
		out.mode = str(config.get("mode", "watch"))
		out.matches = maxi(1, int(config.get("matches", 1)))
		out.defenders = int(config.get("defenders", 1))
		out.invaders = int(config.get("invaders", 1))
		return out


## matches: one unit per match. It starts each match itself, ends it at the MatchHUD's
## match_ended(verdict) or caps it, and records its outcome and its cost (see the header).
class Matches:
	## Game seconds past Main's endless_time_limit before the probe ends a match itself (the
	## MatchHUD calls an Endless match a draw at the limit; a Watch match has no limit of its own).
	const CAP_GRACE := 0.25
	const CAP_VERDICT := "TIME CAP"

	## the probe (its units and its hit file)
	var probe: Node
	## the run config
	var run: Run
	## the open match's cost meters
	var cost := MatchCost.new()
	## the open match's number, from 1
	var _match := 0
	## the open match's world has appeared, so its clock runs
	var _started := false
	## physics frames since the open match's world appeared
	var _frames := 0
	## Main's endless_time_limit
	var _limit := 0.0
	## the last match is decided; the process is quitting
	var _ending := false
	## the EventBus autoload (null = the game has none: shots not counted)
	var _bus: Node

	func _init(owner: Node, config: Run) -> void:
		probe = owner
		run = config

	## Find Main's hooks, then start the first match.
	func start() -> void:
		await probe.get_tree().process_frame  # the main scene's _ready has run
		var main := probe.get_tree().current_scene
		if main == null or not ("endless_time_limit" in main):
			probe.fail(
				"the main scene has no endless_time_limit (Main's export; a parse error in Main's"
				+ " script leaves it out: see the game log), so no match can be capped",
			)
			return
		var menu := _find_with_signal(main, &"start_requested")
		if menu == null:
			probe.fail(
				"the setup window's start_requested signal was not found under the main"
				+ " scene",
			)
			return
		var hud := _find_with_signal(main, &"match_ended")
		if hud == null:
			probe.fail("the MatchHUD's match_ended signal was not found under the main scene")
			return
		hud.connect(&"match_ended", _on_match_ended)
		_bus = probe.get_tree().root.get_node_or_null(^"EventBus")
		if _bus != null and _bus.has_signal(&"posted"):
			_bus.connect(&"posted", _on_posted)
		else:
			_bus = null
		_limit = float(main.get("endless_time_limit"))
		probe.get_tree().node_added.connect(_on_match_node_added)
		_open_match()
		menu.emit_signal(
			&"start_requested",
			{
				"mode": run.mode, "seed": run.seed_value,
				"lead": false, "defenders": { "count": run.defenders },
				"invaders": { "count": run.invaders },
			},
		)

	## A process frame: the open match's process time.
	func process_frame() -> void:
		if _started and not _ending:
			cost.process_sum += Performance.get_monitor(Performance.TIME_PROCESS)
			cost.process_n += 1

	## A physics frame: the open match's clock and physics time, and its cap.
	func physics_frame() -> void:
		if not _started or _ending:
			return
		_frames += 1
		cost.physics_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		cost.physics_n += 1
		if _frames >= (_limit + CAP_GRACE) * Engine.physics_ticks_per_second:
			_end_match(CAP_VERDICT, true)

	## Open the next match's unit; its clock waits for the match's world (_on_match_node_added).
	func _open_match() -> void:
		_match += 1
		_frames = 0
		probe.open_unit({
			"id": "%d-%d" % [run.seed_value, _match], "seed": run.seed_value,
			"mode": run.mode, "match": _match, "verdict": "", "duration": 0.0,
		})
		_started = false

	## The open match's world joined the tree: its clock, its outcome and its cost start now.
	func _on_match_node_added(node: Node) -> void:
		if node.has_signal(&"decided") and node.has_signal(&"failed"):
			node.connect(&"decided", _on_decided)
			node.connect(&"failed", _on_undecided)
		if _started or _ending or probe.unit.is_empty() or not node.is_in_group(&"match_world"):
			return
		_started = true
		_frames = 0
		cost.start()

	## A decision planner (a node with the signals `decided(leaf)` and `failed()`) ended a walk with
	## Von's answer.
	func _on_decided(_leaf: Dictionary) -> void:
		if _started and not _ending:
			cost.decided += 1

	## A decision planner ended a walk without an answer (Von timed out or gave a bad pick: the NPC
	## holds steady).
	func _on_undecided() -> void:
		if _started and not _ending:
			cost.undecided += 1

	## An EventBus post: a `shot` counts toward the open match's shots.
	func _on_posted(topic: StringName, _data: Dictionary) -> void:
		if topic == &"shot" and _started and not _ending:
			cost.shots += 1

	## The MatchHUD decided the open match.
	func _on_match_ended(verdict: String) -> void:
		if not probe.unit.is_empty() and not _ending:
			_end_match(verdict, false)

	## Decide the open match. The next one opens at once (its unit holds the teardown and the pause
	## before it); after the last one, or a capped one, the process quits and the hits until then
	## stay with this match.
	func _end_match(verdict: String, capped: bool) -> void:
		if not _started:
			probe.fail(("match %d ended (%s) before any node of the group match_world appeared: "
						+ "the world Main builds a match in, which a match is timed from, was not "
						+ "found")
					% [_match, verdict])
			return
		probe.collect()
		var open: Dictionary = probe.unit
		open["verdict"] = verdict
		cost.record(open, _frames, _bus != null, _deaths())
		open.merge(_von_rate(open["duration"]), true)
		if _match < run.matches and not capped:
			probe.close_unit()
			_open_match()
			return
		_ending = true
		_quit.call_deferred()

	## The characters dead as the match ends (null when no node is in the group `characters`).
	func _deaths() -> Variant:
		var characters := probe.get_tree().get_nodes_in_group(&"characters")
		if characters.is_empty():
			return null
		var dead := 0
		for c in characters:
			if c.get("is_dead") == true:
				dead += 1
		return dead

	## How often the match's NPCs got a Von decision: `npcs` (the AI controllers, the group
	## `npc_controllers`, as it ends), `decisions` (their debug_state() `decisions`, the walks
	## started, summed), `decided` and `failed` (the walks the decision planners ended with Von's
	## answer and without one, counted from their signals during the match),
	## `decided_per_npc_minute` (decided per NPC per game minute) and `von_failed_share` (failed /
	## (decided + failed); null when no walk ended). A starved Von server times its walks out: walks
	## keep starting at the decide cadence while few are decided, so the decided rate is the one a
	## starved match shows in. With no controller, all but `npcs` are null.
	func _von_rate(duration: float) -> Dictionary:
		var controllers := probe.get_tree().get_nodes_in_group(&"npc_controllers")
		var out := { "npcs": controllers.size(), "decisions": null, "decided": null, "failed": null,
			"decided_per_npc_minute": null, "von_failed_share": null }
		if controllers.is_empty():
			return out
		var decisions := 0
		for c in controllers:
			var state: Dictionary = c.debug_state()
			decisions += int(state.get("decisions", 0))
		out["decisions"] = decisions
		out["decided"] = cost.decided
		out["failed"] = cost.undecided
		out["decided_per_npc_minute"] = (cost.decided / float(controllers.size())
				/ maxf(duration / 60.0, 1.0 / 3600.0))
		if cost.decided + cost.undecided > 0:
			out["von_failed_share"] = cost.undecided / float(cost.decided + cost.undecided)
		return out

	## Flush, then quit the game (after the last match).
	func _quit() -> void:
		probe.flush()
		probe.get_tree().quit()

	## The first node under `root` (breadth first, `root` included) with the signal `signal_name`,
	## or null.
	func _find_with_signal(root: Node, signal_name: StringName) -> Node:
		var queue: Array[Node] = [root]
		while not queue.is_empty():
			var node: Node = queue.pop_front()
			if node.has_signal(signal_name):
				return node
			queue.append_array(node.get_children())
		return null


## matches: the open match's cost meters, all from its world on.
class MatchCost:
	## `shot` posts
	var shots := 0
	## decision planners' `decided` signals
	var decided := 0
	## decision planners' `failed` signals
	var undecided := 0
	## Time.get_ticks_usec() when the world appeared
	var _wall_start := 0
	## Engine.get_process_frames() when the world appeared
	var _frame_start := 0
	## TIME_PHYSICS_PROCESS summed over the match's physics frames
	var physics_sum := 0.0
	## the physics frames in physics_sum
	var physics_n := 0
	## TIME_PROCESS summed over the match's process frames
	var process_sum := 0.0
	## the process frames in process_sum
	var process_n := 0

	## Zero the meters and stamp the clocks: the match's world appeared.
	func start() -> void:
		shots = 0
		decided = 0
		undecided = 0
		_wall_start = Time.get_ticks_usec()
		_frame_start = Engine.get_process_frames()
		physics_sum = 0.0
		physics_n = 0
		process_sum = 0.0
		process_n = 0

	## Write the match's outcome and cost into its unit `out`: its `duration` from `frames` (physics
	## frames), `shots` (null unless `bus_seen`), `deaths`, `wall`, `frames` and the two peaks.
	func record(out: Dictionary, frames: int, bus_seen: bool, deaths: Variant) -> void:
		out["duration"] = float(frames) / Engine.physics_ticks_per_second
		out["shots"] = null
		if bus_seen:
			out["shots"] = shots
		out["deaths"] = deaths
		out["wall"] = (Time.get_ticks_usec() - _wall_start) / 1_000_000.0
		out["frames"] = Engine.get_process_frames() - _frame_start
		out["physics_peak_ms"] = physics_sum * 1000.0 / maxi(1, physics_n)
		out["process_peak_ms"] = process_sum * 1000.0 / maxi(1, process_n)


## tests: one unit per test, following the game test suites (see the header).
class Tests:
	## the group the game's test suites join (scenes/testing/game_test_suite.gd GROUP)
	const RUNNER_GROUP := &"game_test_suites"

	## the probe (its units)
	var probe: Node
	## a suite has joined the group in this process
	var found_runner := false
	## the game test suite running now (null between suites)
	var _runner: Node
	## the id of the test the open unit belongs to
	var _test_id := ""

	func _init(owner: Node) -> void:
		probe = owner

	## Watch for the game test suites: each joins RUNNER_GROUP as gdUnit adds it to the tree, and
	## its tests open and end while it is there. Called deferred from _ready, so it is listening
	## before the first suite is added.
	func start() -> void:
		probe.open_unit(_outside_unit())  # the start-up so far, until the first test
		probe.get_tree().node_added.connect(_on_node_added)
		for node in probe.get_tree().get_nodes_in_group(RUNNER_GROUP):
			_adopt(node)
		check()

	## When the test running changed (one opened, or the open one finished), the hits so far belong
	## to the unit before.
	func check() -> void:
		if not is_instance_valid(_runner):
			return
		var ctx: Variant = _runner.get("open_ctx")
		var live := is_instance_valid(ctx)
		if live and not ("is_finished" in ctx and ctx.has_signal(&"finished")):
			_runner = null
			probe.fail(
				"the game test suite's test context (open_ctx) has no is_finished"
				+ " or no finished signal",
			)
			return
		var entry: Variant = _runner.get("open_entry")
		var running: bool = live and ctx.get("is_finished") == false and entry is Dictionary
		var id := str(entry.get("id", "")) if running else ""
		if id == _test_id:
			return
		probe.collect()
		probe.close_unit()
		_test_id = id
		probe.open_unit({ "id": id } if id != "" else _outside_unit())
		if id != "":
			_listen_for_end(ctx)

	## A node joined the tree: a suite that starts its tests now, or a node of the open suite's
	## test (it adds the test's world once its context is open).
	func _on_node_added(node: Node) -> void:
		if node != _runner and node.is_in_group(RUNNER_GROUP):
			_adopt(node)
		check()

	## Follow the suite `node` from now on, once it is seen to have the hooks (`open_entry`,
	## `open_ctx`).
	func _adopt(node: Node) -> void:
		if not ("open_entry" in node):
			probe.fail("the game test suite's current entry (open_entry on %s) was not found"
					% node.name)
			return
		if not ("open_ctx" in node):
			probe.fail("the game test suite's test context (open_ctx on %s) was not found"
					% node.name)
			return
		_runner = node
		found_runner = true

	## The open test's context emitted `finished`: the test is decided, so its unit ends here.
	func _on_test_finished() -> void:
		check()

	## Hear the open test's end first: a listener connected before the probe would run before it,
	## and what it runs then (the runner's teardown) would be charged to the test.
	func _listen_for_end(ctx: Object) -> void:
		if not ctx.get_signal_connection_list(&"finished").is_empty():
			_runner = null
			probe.fail(("something listens to test %s's finished before the probe could (the "
						+ "suite should add the test's world before it waits for the end): its "
						+ "teardown would be charged to the test")
					% _test_id)
			return
		ctx.connect(&"finished", _on_test_finished, CONNECT_ONE_SHOT)

	## The unit of the hits made while no test runs.
	func _outside_unit() -> Dictionary:
		return { "id": "", "outside": true }
