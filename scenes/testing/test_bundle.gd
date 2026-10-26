extends RefCounted
## Testing domain: what a failed run's bundle carries (test_context.gd's `bundle`): the traces the
## test sampled, its screenshots, and the plain-data state of the world and of its event log. It
## holds nothing of its context (an Object the session frees by hand), only the SceneTree its
## screenshots are taken from.

## Sampled series from the context's `trace()`: name → Array of `[time, value]`.
var traces: Dictionary = {}
## Where `screenshot()` saves PNGs, as a path prefix ("" = screenshots off; the runner's `--shots`
## sets it on a rendering run). `shots` lists the files written.
var shot_prefix := ""
var shots: Array = []
## The tree whose root viewport a screenshot is taken of.
var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree


## Save the current frame as a PNG named after `label` and return its absolute path, or "" when
## screenshots are off (`--shots` not given) or there is no rendering (headless). Failed runs under
## `--shots` also get one automatically.
func screenshot(label: String) -> String:
	if shot_prefix == "" or DisplayServer.get_name() == "headless":
		return ""
	var image := _tree.root.get_texture().get_image()
	if image == null:
		return ""
	var path := "%s__%s.png" % [shot_prefix, label.validate_filename()]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) != OK:
		return ""
	var absolute := ProjectSettings.globalize_path(path)
	shots.append(absolute)
	return absolute


## The state of every actor, object and vehicle `world` (a TestWorld) placed, right now, as plain
## data for a failure bundle: position, health/death, held item, and an NPC brain's decision path
## (its controller child in the group `npc_controllers`). Freed nodes are skipped, so take it before
## the world is torn down; a freed or missing world gives none.
func snapshot(world: Variant) -> Dictionary:  # untyped: the world may have been freed
	var out := { "actors": {}, "objects": {}, "vehicles": {} }
	if not is_instance_valid(world):
		return out
	for id in world.actors:
		var a: Variant = world.actors[id]  # untyped: a freed node may not be assigned to a Node
		if is_instance_valid(a):
			out["actors"][String(id)] = _actor_state(a)
	for id in world.objects:
		var o: Variant = world.objects[id]
		if is_instance_valid(o) and o is Node2D:
			out["objects"][String(id)] = { "position": _vec(o.global_position) }
	for id in world.vehicles:
		var v: Variant = world.vehicles[id]
		if is_instance_valid(v) and v is Node2D:
			out["vehicles"][String(id)] = _vehicle_state(v)
	return out


## The event log `events` (the context's `{ topic, data, time }` rows) as JSON-safe rows
## `{ topic, time, data }` (nodes become their names).
func plain_events(events: Array) -> Array:
	return events.map(
		func(e):
			return {
				"topic": String(e["topic"]),
				"time": snappedf(e["time"], 0.01),
				"data": _plain(e["data"]),
			}
	)


## One actor's row of `snapshot`: its position, health/death, faction and move input, and an NPC
## brain's decision path and status.
func _actor_state(a: Node) -> Dictionary:
	var s := { "position": _vec(a.global_position) if a is Node2D else "" }
	for prop in ["health", "max_health", "is_dead", "faction"]:
		if prop in a:
			s[prop] = _plain(a.get(prop))
	if "movement" in a:
		s["move_input"] = _plain(a.movement.move_input)
	for child in a.get_children():
		if child.is_in_group(&"npc_controllers"):
			var act: Variant = child.current_act()
			s["act"] = ("/".join(PackedStringArray(act.map(func(x): return str(x))))
					if act is Array
					else str(act))
			s["status"] = str(child.debug_status())
	return s


## One vehicle's row of `snapshot`: its position, rotation and, when it has one, speed.
func _vehicle_state(v: Node2D) -> Dictionary:
	var row := {
		"position": _vec(v.global_position),
		"rotation": snappedf(v.global_rotation, 0.01),
	}
	if v.has_method("speed"):
		row["speed"] = snappedf(v.speed(), 0.1)
	return row


## Formats a Vector2 as a rounded "(x, y)" string.
static func _vec(v: Vector2) -> String:
	return "(%.0f, %.0f)" % [v.x, v.y]


## `v` reduced to JSON-safe values: nodes → their names, vectors → text, containers recursed.
static func _plain(v: Variant) -> Variant:
	if typeof(v) == TYPE_OBJECT:
		return _plain_object(v)
	if v is Vector2:
		return _vec(v)
	if v is Dictionary or v is Array:
		return _plain_container(v)
	if v is StringName:
		return String(v)
	if v == null or v is bool or v is int or v is float or v is String:
		return v
	return str(v)


## An object reduced as `_plain` does: a node its name, a freed one "<freed>", any other its text.
static func _plain_object(v: Variant) -> String:
	if not is_instance_valid(v):
		return "<freed>"
	return String(v.name) if v is Node else str(v)


## A Dictionary (keys as text) or an Array with each value reduced by `_plain`.
static func _plain_container(v: Variant) -> Variant:
	if v is Array:
		return v.map(func(x): return _plain(x))
	var d := {}
	for k in v:
		d[str(k)] = _plain(v[k])
	return d
