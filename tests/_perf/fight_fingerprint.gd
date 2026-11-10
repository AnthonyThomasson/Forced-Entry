extends RefCounted
## A fight's fingerprint: one line per physics frame of everything a revision's fight is made of, so
## two plays of one match can be diffed and the first frame they differ on named
## (perf-fingerprint.md of the domain-testing skill). Load it with
## `const Fingerprint := preload(...)`; the match guards reach it through `Perf.record_fight`. Not a
## test (no `_test.gd` suffix).
##
## It costs nothing unset: `begin` returns null unless the environment holds
## `GAME_TEST_FINGERPRINT_DIR` (`tools/run_tests.sh` passes it to every engine process), and no
## signal is connected.
##
## A line is tab-separated fields: the frame number (0 on the first physics frame after `begin`),
## one field per NPC in the order given (spawn order), then `S:` and `D:`:
##   <frame> TAB <i> <x>,<y> <gx>,<gy> <act> <health> TAB ... TAB S:<x>,<y>;<x>,<y> TAB D:<i>,<i>
## `i` is the NPC's index in the order given, never its node name or instance id (both follow
## allocation); `x,y` its position rounded to whole pixels; `gx,gy` its navigation agent's target
## rounded (`-` with none); `act` the controller's decision path (`current_act()`, `-` for a
## character with no AI controller); `health` to one decimal (`gone` for a freed NPC, alone in its
## field). `S:` lists this frame's shots, the muzzle rounded, in the order they were posted; `D:`
## the indices of the NPCs that died this frame.

## The environment variable that turns the fingerprint on: the directory the files are written to.
const ENV_DIR := "GAME_TEST_FINGERPRINT_DIR"

var _t: TestContext
var _tree: SceneTree
var _npcs: Array
var _file: FileAccess
var _frame := 0
var _events_seen := 0
var _was_dead: Array[bool] = []


## Start recording `npcs` (Nodes, in spawn order) of the running test `t` into
## `<dir>/<test id with / as __>.fp`. `test_id` is `domain/name` (`test_id_of`). `dir` is the
## environment's by default; empty gives null and records nothing. The file is written as the
## frames run and closed when the world is freed (or by `close`). Returns the recorder or null.
static func begin(
	t: TestContext,
	test_id: String,
	npcs: Array,
	dir := OS.get_environment(ENV_DIR),
) -> RefCounted:
	if dir == "":
		return null
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path_for(dir, test_id), FileAccess.WRITE)
	if file == null:
		push_error(
			"Fingerprint: cannot write %s (error %d)"
			% [path_for(dir, test_id), FileAccess.get_open_error()]
		)
		return null
	var recorder := new()
	recorder._t = t
	recorder._tree = t.world.get_tree()
	recorder._npcs = npcs.duplicate()
	recorder._file = file
	recorder._was_dead.resize(npcs.size())
	recorder._was_dead.fill(false)
	recorder._tree.physics_frame.connect(recorder._on_frame)
	t.world.tree_exiting.connect(recorder.close)
	return recorder


## The file a test's fingerprint goes to under `dir`: its id with every `/` as `__`, then `.fp`.
static func path_for(dir: String, test_id: String) -> String:
	return dir.path_join(test_id.replace("/", "__") + ".fp")


## The id (`domain/name`) of the test whose script is `test`'s: its path under `tests/` without the
## `_test.gd` suffix.
static func test_id_of(test: GameTest) -> String:
	return test.get_script().resource_path.trim_prefix("res://tests/").trim_suffix("_test.gd")


## Stop recording and close the file. Safe to call twice.
func close() -> void:
	if _file == null:
		return
	if _tree.physics_frame.is_connected(_on_frame):
		_tree.physics_frame.disconnect(_on_frame)
	_file.close()
	_file = null


func _on_frame() -> void:
	if _file == null or _t.is_finished:
		return
	var fields: PackedStringArray = [str(_frame)]
	var died: PackedStringArray = []
	for i in _npcs.size():
		var npc: Variant = _npcs[i]
		fields.append("%d %s" % [i, _state(npc)])
		if is_instance_valid(npc) and npc.get("is_dead") == true and not _was_dead[i]:
			_was_dead[i] = true
			died.append(str(i))
	fields.append("S:" + ";".join(_shots_since_last_frame()))
	fields.append("D:" + ",".join(died))
	_file.store_line("\t".join(fields))
	# Flushed each frame: a process that ends with the world still up (the last test of a run)
	# closes no file, and the engine's buffer would be lost.
	_file.flush()
	_frame += 1


## `x,y gx,gy act health` of one NPC, or `gone` once it is freed.
func _state(npc: Variant) -> String:
	if not is_instance_valid(npc):
		return "gone"
	var brain := TestContext.controller_of(npc, &"current_act")
	var agent: NavigationAgent2D = npc.get_node_or_null("NavigationAgent2D")
	return "%s %s %s %.1f" % [
		_point(npc.global_position),
		_point(agent.target_position) if agent != null else "-",
		brain.current_act() if brain != null else "-",
		npc.get("health"),
	]


## The shots the event log took since the last frame, each its muzzle rounded.
func _shots_since_last_frame() -> PackedStringArray:
	var out: PackedStringArray = []
	var events := _t.events
	for i in range(_events_seen, events.size()):
		if events[i]["topic"] == &"shot":
			out.append(_point(events[i]["data"].get("position", Vector2.ZERO)))
	_events_seen = events.size()
	return out


static func _point(p: Vector2) -> String:
	return "%d,%d" % [roundi(p.x), roundi(p.y)]
