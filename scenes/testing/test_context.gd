class_name TestContext extends Object
## Testing domain: what a running test sees — handed to `GameTest.run(t)`. Waiting (in sim time),
## looking up what the setup placed, the event log of what happened, and the assertions. Its
## `verdict` part (test_verdict.gd) keeps the checks and judges the run; its `bundle` part
## (test_bundle.gd) keeps what a failed run's bundle carries (traces, screenshots, the plain-data
## state). The session sets `world`, `rooms` and `time` and appends to `events`.
##
## Once the test has ended (a failed `require`, a logged error, a timeout, `skip`), every wait
## suspends until the runner frees this context (an Object, so freeing it discards the parked
## coroutines), so a test coroutine never runs on into a torn-down world. Code between a failed
## `require` and the next wait still runs, so guard it: `if not t.require(...): return`.

## Emitted once when the test ends, for whatever reason.
signal finished
## Never emitted: waits park on it once the test has ended.
signal _never


# --- Input ----------------------------------------------------------------------------------

## Marks an input event a test sent itself, so a locked interaction (`TestSetup.lock_interaction`)
## lets it through while still dropping the same kind of event from a person.
const INJECTED_META := &"test_injected"
const TestVerdict = preload("res://scenes/testing/test_verdict.gd")
const TestBundle = preload("res://scenes/testing/test_bundle.gd")

## The built world (a TestWorld node) and its rooms (`{ key, type, rect }`, world-space).
var world: Node2D
var rooms: Array = []
## Sim seconds since the test started (advanced by the runner each physics frame).
var time := 0.0
## Everything observed, in order: `{ topic, data, time }`. Topics: every EventBus topic (`&"hit"`,
## `&"callout"`, …), plus `&"died"` / `&"hit_landed"` per actor (`data.actor` = its id) and
## `&"spawned"` / `&"removed"` for nodes entering/leaving the world root (`data.node`, `data.name`).
var events: Array = []
## Whether the test has ended (`finish`: a verdict, a failed `require`, a skip); a wait then parks
## for good.
var is_finished := false
## The checks and the verdict (test_verdict.gd).
var verdict: TestVerdict
## What a failed run's bundle carries (test_bundle.gd).
var bundle: TestBundle
## The tree whose physics frames the waits count.
var _tree: SceneTree


func _init(tree: SceneTree, description: Dictionary) -> void:
	_tree = tree
	verdict = TestVerdict.new(description)
	bundle = TestBundle.new(tree)


# --- Lookup -------------------------------------------------------------------------------


## The character placed as `id` (null if unknown or freed).
func actor(id: StringName) -> Node:
	# untyped: a freed node may not be assigned to a Node
	var n: Variant = world.actors.get(id) if is_instance_valid(world) else null
	return n if is_instance_valid(n) else null


## The puppet controller of actor `id` (null when it isn't a puppet).
func puppet(id: StringName) -> Node:
	var a := actor(id)
	if a == null:
		return null
	for child in a.get_children():
		if child.has_method("walk_to"):
			return child
	return null


## The object placed as `id` (null if unknown or freed).
func object(id: StringName) -> Node:
	# untyped: assigning a freed object to a Node variable is an engine error
	var n = world.objects.get(id) if is_instance_valid(world) else null
	return n if is_instance_valid(n) else null


## The vehicle placed as `id` (`TestSetup.vehicle`; null if unknown, freed, or its kind has no
## scene).
func vehicle(id: StringName) -> Node:
	# untyped, as in `object`
	var n = world.vehicles.get(id) if is_instance_valid(world) else null
	return n if is_instance_valid(n) else null


## A child controller of actor `id` that has `method` (e.g. an NPC's `current_act`), or null.
func controller(id: StringName, method := &"control") -> Node:
	var a := actor(id)
	if a == null:
		return null
	return controller_of(a, method)


## The child of `character` that has `method` (default `control`: its controller, interface 7), or
## null. For characters that are not test actors (a match's NPCs spawned in `run`).
static func controller_of(character: Node, method := &"control") -> Node:
	for child in character.get_children():
		if child.has_method(method):
			return child
	return null


## Send `event` into the game as the test's own input (instead of a bare `Input.parse_input_event`).
static func inject(event: InputEvent) -> void:
	event.set_meta(INJECTED_META, true)
	Input.parse_input_event(event)


# --- Waiting (sim time) ---------------------------------------------------------------------


## Wait `duration` seconds of simulated time.
func seconds(duration: float) -> void:
	var until_time := time + duration
	while time < until_time and not is_finished:
		await _tree.physics_frame
	if is_finished:
		await _never


## Wait `count` physics frames.
func frames(count: int) -> void:
	for i in count:
		await _tree.physics_frame
		if is_finished:
			break
	if is_finished:
		await _never


## Wait until `condition` returns true or `timeout` sim seconds pass. Returns whether it came true.
## With a `message`, a timeout also records a failed check.
func until(condition: Callable, timeout: float, message := "") -> bool:
	var deadline := time + timeout
	while not is_finished:
		if condition.call():
			return true
		if time >= deadline:
			if message != "":
				check(false, message + " (waited %.1fs)" % timeout)
			return false
		await _tree.physics_frame
	await _never
	return false


# --- Event log ------------------------------------------------------------------------------


## Logged events with `topic`, optionally filtered by `filter(data) -> bool`.
func events_of(topic: StringName, filter := Callable()) -> Array:
	var out: Array = []
	for e in events:
		if e["topic"] == topic and (not filter.is_valid() or filter.call(e["data"])):
			out.append(e["data"])
	return out


## Whether any event with `topic` (passing `filter`) has happened.
func happened(topic: StringName, filter := Callable()) -> bool:
	return not events_of(topic, filter).is_empty()


## Nodes that entered the world root whose name contains `name_part` (e.g. "BloodSplat").
func spawned(name_part: String) -> Array:
	var out: Array = []
	for data in events_of(&"spawned"):
		if String(data["name"]).contains(name_part):
			out.append(data["node"])
	return out


## Record `value` (a number) under `name` at the current time, e.g. a distance a threshold check
## later misses. Failed runs print each series' range and last value and keep it in the failure
## bundle.
func trace(trace_name: String, value: float) -> void:
	var series: Array = bundle.traces.get(trace_name, [])
	series.append([snappedf(time, 0.01), snappedf(value, 0.001)])
	bundle.traces[trace_name] = series


# --- Assertions -----------------------------------------------------------------------------


## Record `condition` as a check; returns it. A failure fails the test but lets it continue.
func check(condition: bool, message: String) -> bool:
	verdict.checks.append({ "ok": condition, "message": message, "time": time })
	return condition


## Like `check`, but a failure also ends the test. Returns `condition`.
func require(condition: bool, message: String) -> bool:
	check(condition, message)
	if not condition:
		finish("FAIL")
	return condition


## Check `actual == expected`.
func expect_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])


## Check `|actual - expected| <= tolerance`.
func expect_near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s (got %.3f, expected %.3f ± %.3f)" % [message, actual, expected, tolerance])


## End the test as SKIPPED.
func skip(why: String) -> void:
	verdict.reason = why
	finish("SKIPPED")


# --- Runner-facing --------------------------------------------------------------------------


## End the test with `result` (first call wins). Waits park; `finished` fires.
func finish(result: String) -> void:
	if is_finished:
		return
	is_finished = true
	verdict.end(result)
	finished.emit()
