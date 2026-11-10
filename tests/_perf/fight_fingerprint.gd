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
## rounded (`-` with none); `act` the controller's decision path (`current_act()`, every instance
## id in it written as the NPC's index, or the object's rounded position, `act_text`; `-` for a
## character with no AI controller; it can hold a space); `health` to one decimal (`gone` for a
## freed NPC, alone in its field). `S:` and `D:` are what happened since the previous line (the step
## before this frame's state): the shots, the muzzle rounded, in the order they were posted, and
## the indices of the NPCs that died.

## The environment variable that turns the fingerprint on: the directory the files are written to.
const ENV_DIR := "GAME_TEST_FINGERPRINT_DIR"
## The meta of the test's world that holds the recorder: a signal connection holds no reference to
## a RefCounted, so nothing else would keep it (and its file) alive once `begin` returned.
const META := &"fight_fingerprint"
## The digits an instance id has at least (Godot's are 13 here); a shorter number in an act is not
## one.
const ID_DIGITS := 9

var _t: TestContext
var _tree: SceneTree
var _npcs: Array
var _file: FileAccess
var _frame := 0
var _events_seen := 0
var _was_dead: Array[bool] = []
## Indices of the NPCs whose `died` signal fired since the last line.
var _died_signalled: Array[int] = []
## NPC instance id -> its index in `_npcs`, for the ids an act names (`act_text`).
var _index_of := {}


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
	for i in npcs.size():
		recorder._index_of[npcs[i].get_instance_id()] = i
	recorder._was_dead.resize(npcs.size())
	recorder._was_dead.fill(false)
	for i in npcs.size():
		# A death seen on the signal still lands in `D:` when the NPC is freed before a frame reads
		# it.
		if npcs[i].has_signal("died"):
			npcs[i].died.connect(recorder._on_died.bind(i))
	recorder._tree.physics_frame.connect(recorder._on_frame)
	t.world.tree_exiting.connect(recorder.close)
	t.world.set_meta(META, recorder)
	return recorder


## The file a test's fingerprint goes to under `dir`: its id with every `/` as `__`, then `.fp`.
static func path_for(dir: String, test_id: String) -> String:
	return dir.path_join(test_id.replace("/", "__") + ".fp")


## The id (`domain/name`) of the test whose script is `test`'s: its path under `tests/` without the
## `_test.gd` suffix.
static func test_id_of(test: GameTest) -> String:
	return test.get_script().resource_path.trim_prefix("res://tests/").trim_suffix("_test.gd")


## `act` with every instance id in it made stable: an NPC's becomes its index in the match
## (`index_of`: instance id -> index), another node's its rounded position (`@x,y`), a freed or
## unknown one `?`. A decision's option id names a hostile (`t_<id>`, `lead_seen_<id>`,
## `lead_heading_<id>`, `lead_ally_<id>`: `snapshot_options.gd`) or an object (`do_<id>_<action>`),
## and an instance id follows allocation. An id is a run of nine digits or more or any number
## in `index_of`; shorter numbers (a grid cell, `door_0`) are kept.
static func act_text(act: String, index_of: Dictionary) -> String:
	var out := ""
	var at := 0
	for m in RegEx.create_from_string("\\d+").search_all(act):
		var digits := m.get_string()
		var id := int(digits)
		out += act.substr(at, m.get_start() - at)
		at = m.get_end()
		if index_of.has(id):
			out += str(index_of[id])
		elif digits.length() >= ID_DIGITS:
			var node := (
				instance_from_id(id) as Node2D if is_instance_id_valid(id) else null
			)
			out += "?" if node == null else "@" + _point(node.global_position)
		else:
			out += digits
	return out + act.substr(at)


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
		var dead: bool = _died_signalled.has(i) or (
			is_instance_valid(npc) and npc.get("is_dead") == true
		)
		if dead and not _was_dead[i]:
			_was_dead[i] = true
			died.append(str(i))
	_died_signalled.clear()
	fields.append("S:" + ";".join(_shots_since_last_frame()))
	fields.append("D:" + ",".join(died))
	_file.store_line("\t".join(fields))
	# Flushed each frame: a process that ends with the world still up (the last test of a run)
	# closes no file, and the engine's buffer would be lost.
	_file.flush()
	_frame += 1


func _on_died(index: int) -> void:
	_died_signalled.append(index)


## `x,y gx,gy act health` of one NPC, or `gone` once it is freed.
func _state(npc: Variant) -> String:
	if not is_instance_valid(npc):
		return "gone"
	var brain := TestContext.controller_of(npc, &"current_act")
	var agent: NavigationAgent2D = npc.get_node_or_null("NavigationAgent2D")
	return "%s %s %s %.1f" % [
		_point(npc.global_position),
		_point(agent.target_position) if agent != null else "-",
		act_text(brain.current_act(), _index_of) if brain != null else "-",
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
