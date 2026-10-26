extends Node
## Testing domain: plays one catalog test at a time under this node, the core the in-game runner
## (test_runner.gd) and the gdUnit base suite (game_test_suite.gd) share. `start(entry)` builds the
## test's TestWorld from its `configure` as a child, observes it on a TestContext (EventBus events,
## each actor's `died` / `hit_landed`, the nodes spawned under and removed from the world), runs the
## test's `run` against it and returns once the test has ended. Its sim clock ticks each physics
## frame (not while the tree is paused, nor while the world builds) and ends it as TIMEOUT at its
## declared timeout; every engine error or warning the host's LogWatch reads meanwhile goes to the
## test and fails it at once (log_watch.gd), and one read while no test is open is kept in
## `stray_logs`. `close()` frees the world (restoring statics), lets the teardown's logs land on the
## test and returns its verdict record. A requires_von test waits for the Von decision server (one
## launcher kept under `von.launcher_parent` while it lives) and runs paced in real time, through
## the `von` part (test_von_gate.gd).

## A status line for the host's banner ("Waiting for the decision server…").
signal status(text: String)
## The test's setup is configured and its world is about to be built (the host reads `setup.locked`,
## its actors).
signal configured(setup: TestSetup)
## The test's world is built and bound: the host frames its camera on it and builds its overlays.
signal world_built(setup: TestSetup)
## A log line read after the verdict was taken changed it: the host shows the new record.
signal verdict_changed(result: Dictionary)

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const TestWorldScript = preload("res://scenes/testing/test_world.gd")
const LogWatch = preload("res://scenes/testing/log_watch.gd")
const VonGate = preload("res://scenes/testing/test_von_gate.gd")
## The verdicts that carry a bundle (event log, final state, traces) and a `--shots` screenshot.
const BUNDLED := ["FAIL", "TIMEOUT", "GAP"]

## The engine log tail whose errors and warnings fail the open test (the host's; set before the
## first `start`).
var watch: LogWatch = null
## The Von gate: whether requires_von tests run (`include`, `require`), where its launcher lives
## (`launcher_parent`), the wait for the server and the real-time pacing of a Von test.
var von: VonGate = VonGate.new(self)
## `--shots`: the open test saves screenshots (a failed one automatically) under `bundle_dir`.
var shots := false
## Where the open test's bundle and screenshots go.
var bundle_dir := ""
## The open test's descriptor ({} between tests; the setup, context and world below are null then).
var entry: Dictionary = {}
## The open test's setup, as its `configure` declared it.
var setup: TestSetup = null
## The open test's context: its waits, event log and checks.
var ctx: TestContext = null
## The open test's world, built from its setup.
var world: Node2D = null
## Errors and warnings read while no test was open.
var stray_logs: Array = []
## The world is still being built: the test clock waits (the build may wait in real time for the
## navigation map).
var _building := false
## Whether the open test's verdict has been taken (a later logged error then changes it).
var _concluded := false


func _process(_delta: float) -> void:
	von.pace()


func _physics_process(delta: float) -> void:
	poll_logs()
	if get_tree().paused:
		return  # the test clock (and so its timeout and waits) stops with the world
	if ctx != null and not ctx.is_finished and not _building:
		ctx.time += delta
		if (not entry.get("manual", false)
				and ctx.time >= float(entry.get("timeout", TestCatalog.DEFAULT_TIMEOUT))):
			ctx.reason = "timed out after %.1fs" % float(entry["timeout"])
			ctx.finish("TIMEOUT")


func _exit_tree() -> void:
	if ctx != null:
		ctx.free()
		ctx = null


## Read the log and hand each new entry to the open test (`flush`: also one still waiting for its
## location line).
func poll_logs(flush := false) -> void:
	if watch == null:
		return
	for e in watch.poll(flush):
		_route_log(e)


## Build and run the test `test_entry`, leaving its world open. Returns once it has ended.
func start(test_entry: Dictionary) -> void:
	entry = test_entry
	setup = null
	_concluded = false
	var skip_reason := ""
	if entry["requires_von"]:
		skip_reason = await von.skip_reason(status.emit)
	ctx = TestContext.new(get_tree(), entry)
	if skip_reason == VonGate.NOT_LIVE and von.require:
		ctx.check(false, "The Von decision server is not live (--require-von)")
		ctx.finish("FAIL")
		return
	if shots:
		ctx.shot_prefix = "%s/%s" % [bundle_dir, String(entry["id"]).replace("/", "__")]
	if entry["error"] != "":
		ctx.check(false, "Test script " + String(entry["error"]))
		ctx.finish("FAIL")
		return
	if skip_reason != "":
		ctx.skip(skip_reason)
		return
	var test: GameTest = load(entry["path"]).new()
	setup = TestSetup.new()
	test.configure(setup)
	configured.emit(setup)
	_open_world()
	_building = true
	await world.build(setup)
	_building = false
	if not is_instance_valid(world):
		return
	ctx.bind(world, world.actors, world.objects, world.rooms, world.vehicles)
	for id in world.actors:
		_observe_actor(id, world.actors[id])
	world_built.emit(setup)
	_drive(test, ctx)
	if not ctx.is_finished:
		await ctx.finished


## Add the open test's world (pausable), its direct children's arrivals and departures and every
## EventBus event recorded on the test's event log.
func _open_world() -> void:
	world = TestWorldScript.new()
	world.name = "TestWorld"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE  # not inherited from an always-on host
	add_child(world)
	world.child_entered_tree.connect(
		func(n: Node): _on_event(&"spawned", { "node": n, "name": String(n.name) }),
	)
	world.child_exiting_tree.connect(
		func(n: Node): _on_event(&"removed", { "node": n, "name": String(n.name) }),
	)
	EventBus.posted.connect(_on_event)


## Free the open world (restoring statics), let any logs from the teardown land on the test, then
## close it. Returns its verdict record ({} when nothing was open).
func close() -> Dictionary:
	var snapshot := ctx.snapshot() if ctx != null and is_instance_valid(world) else {}
	if shots and ctx != null and is_instance_valid(world):
		if BUNDLED.has(ctx.conclude(entry.get("manual", false))):
			ctx.screenshot("fail")
	if EventBus.posted.is_connected(_on_event):
		EventBus.posted.disconnect(_on_event)
	if is_instance_valid(world):
		world.restore()
		world.queue_free()
		world = null
		await get_tree().physics_frame
		await get_tree().physics_frame
	poll_logs(true)
	von.end()
	var record := result(snapshot) if ctx != null else {}
	if ctx != null:
		ctx.free()  # discards any test coroutine still parked on it
	ctx = null
	return record


## The verdict and record of the open test. A failed, timed-out or GAP result also carries `events`,
## `snapshot` (the final actor / object state, taken before teardown when `snapshot` is passed) and
## `traces`, so the cause can be read without a rerun.
func result(snapshot := {}) -> Dictionary:
	ctx.conclude(entry.get("manual", false))
	_concluded = true
	var record := {
		"id": entry["id"], "name": entry["name"], "domain": entry["domain"],
		"status": ctx.status, "reason": ctx.reason, "time": snappedf(ctx.time, 0.01),
		"checks": ctx.checks.duplicate(), "logs": ctx.logs.duplicate(),
		"manual": entry.get("manual", false),
	}
	if BUNDLED.has(ctx.status):
		record["events"] = ctx.plain_events()
		record["snapshot"] = snapshot if not snapshot.is_empty() else ctx.snapshot()
		record["traces"] = ctx.traces.duplicate(true)
		record["shots"] = ctx.shots.duplicate()
	return record


## The nodes the open world's camera frames: the setup's camera targets (default: every actor); an
## empty world frames its first room, through an anchor node added at its centre.
func camera_targets() -> Array:
	var targets: Array = []
	for id in (setup.camera_targets
				if not setup.camera_targets.is_empty()
				else world.actors.keys()):
		var a: Node = world.actors.get(id)
		if a is Node2D:
			targets.append(a)
	if targets.is_empty() and not world.rooms.is_empty():
		var anchor := Node2D.new()
		anchor.name = "CameraAnchor"
		world.add_child(anchor)
		anchor.global_position = (world.rooms[0]["rect"] as Rect2).get_center()
		targets.append(anchor)
	return targets


## Restore the statics of the open world, if any (before the host leaves the scene with it).
func restore() -> void:
	if is_instance_valid(world):
		world.restore()


## Run the test coroutine; returning normally ends the test (verdict decided in `conclude`).
func _drive(test: GameTest, test_ctx: TestContext) -> void:
	# GameTest.run is not a coroutine itself; the tests that override it are.
	await Callable(test, &"run").call(test_ctx)
	test_ctx.finish("")


## Send a logged line to the open test, or keep it as a stray line.
func _route_log(e: Dictionary) -> void:
	if ctx != null:
		var before := ctx.checks.size()
		ctx.on_log(e)
		if _concluded and ctx.checks.size() != before:
			verdict_changed.emit(result())  # a late error flips a verdict already taken
	elif not LogWatch.matches_any(e, []):
		stray_logs.append(e)


## Log an observed event on the open test (dropped between tests).
func _on_event(topic: StringName, data: Dictionary) -> void:
	if ctx != null:
		ctx.record(topic, data)


## Log an actor's `died` / `hit_landed` signals under its test id.
func _observe_actor(id: StringName, actor: Node) -> void:
	if actor == null:
		return
	if actor.has_signal("died"):
		actor.died.connect(func(): _on_event(&"died", { "actor": id, "node": actor }))
	if actor.has_signal("hit_landed"):
		actor.hit_landed.connect(func(body: Node, damage: float, hand: int):
			_on_event(&"hit_landed", { "actor": id, "body": body, "damage": damage, "hand": hand }))


## Print one verdict record as a batch run does: `<STATUS>  <id>  (<sim>s sim, <ms> ms)  —
## <reason>`, each failed check indented under it, and for a bundled verdict each actor's final
## state, the trace ranges and the `bundle:` path (the bundle is written to `dir` here). `compact`
## (`--summary`) leaves out PASS and SKIPPED.
static func print_result(r: Dictionary, dir: String, compact := false) -> void:
	if compact and (r["status"] == "PASS" or r["status"] == "SKIPPED"):
		return
	var tail: String = "" if r["reason"] == "" else "  — " + String(r["reason"])
	print("%-7s %s  (%.1fs sim, %d ms)%s"
			% [r["status"], r["id"], r["time"], r.get("wall_ms", 0), tail])
	for c in r["checks"]:
		if not c["ok"]:
			print("        ✗ %s" % c["message"])
	if r.has("snapshot"):
		for id in r["snapshot"]["actors"]:
			var a: Dictionary = r["snapshot"]["actors"][id]
			print("        · %s at %s  health %s%s%s" % [
				id, a.get("position", ""), a.get("health", "?"),
				"  DEAD" if a.get("is_dead", false) else "",
				"  act " + a["act"] if a.has("act") else "",
			])
		for trace_name in r["traces"]:
			var series: Array = r["traces"][trace_name]
			var values := series.map(func(p): return p[1])
			print("        ~ %s: min %s  max %s  last %s  (%d samples)"
					% [trace_name, values.min(), values.max(), values.back(), series.size()])
		print("        bundle: %s" % _write_bundle(r, dir))
		for shot in r.get("shots", []):
			print("        shot:   %s" % shot)


## Write a bundled result (events, snapshot, traces included) to `dir`; returns the file's path.
static func _write_bundle(r: Dictionary, dir: String) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.json" % [dir, String(r["id"]).replace("/", "__")]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(r, "  "))
	return ProjectSettings.globalize_path(path)
