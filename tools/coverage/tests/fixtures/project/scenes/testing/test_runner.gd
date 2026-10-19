extends Node
## Fixture stand-in for a game test suite (scenes/testing/game_test_suite.gd; its .tscn puts it in that group,
## game_test_suites): runs its tests one by one from `_ready`, deferred. `open_entry` holds the test running and
## `open_ctx` its context (a Context, with TestContext's `is_finished` and `finished`), both set as it starts; it adds
## the test's world, waits for `finished`, then tears the test down (the teardown) and frees the context. It takes the
## real `--skip-domain=` and `--shard=I/N` flags.

const TESTS := [
	{ "id": "t/alpha", "domain": "t" },
	{ "id": "t/beta", "domain": "t" },
	{ "id": "t/both", "domain": "t" },
	{ "id": "perf/heavy", "domain": "perf" },
]

var open_entry: Dictionary = {}
var open_ctx: Context = null
var _world: Node = null


func _ready() -> void:
	_run_batch.call_deferred()


func _run_batch() -> void:
	var skip: Array = []
	var shard := 0
	var shards := 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--skip-domain="):
			skip = Array(arg.trim_prefix("--skip-domain=").split(","))
		elif arg.begins_with("--shard="):
			var parts := arg.trim_prefix("--shard=").split("/")
			shard = int(parts[0])
			shards = int(parts[1])
	var index := 0
	for entry: Dictionary in TESTS:
		if not skip.has(entry["domain"]) and index % shards == shard:
			await _start(entry)
			await _close()
		index += 1
	get_tree().quit()


func _start(entry: Dictionary) -> void:
	open_entry = entry
	open_ctx = Context.new()
	_world = Node.new()
	add_child(_world)
	_drive(entry)
	if not open_ctx.is_finished:
		await open_ctx.finished


func _drive(entry: Dictionary) -> void:
	await _frames(2)
	var targets = load("res://scenes/game/test_targets.gd").new()
	match entry["id"]:
		"t/alpha":
			targets.alpha()
		"t/beta":
			targets.beta()
		"t/both":
			targets.alpha()
			targets.beta()
		_:
			targets.heavy()
	await _frames(2)
	open_ctx.finish()


func _close() -> void:
	load("res://scenes/game/test_targets.gd").new().teardown()
	_world.queue_free()
	_world = null
	await _frames(2)
	open_ctx.free()
	open_ctx = null


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## The test's context: `finish` ends the test, setting `is_finished` and emitting `finished`.
class Context extends Object:
	signal finished

	var is_finished := false

	func finish() -> void:
		is_finished = true
		finished.emit()
