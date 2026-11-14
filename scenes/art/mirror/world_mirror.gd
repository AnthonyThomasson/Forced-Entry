class_name WorldMirror
extends Node3D
## Art domain, the 3D mirror (interface 27, `docs/adr/0013-the-3d-render-mirrors-the-2d-sim.md`):
## the registry that follows every drawn 2D body in a `Node3D` world. Each body under the root it is
## given gets a proxy per collision shape, a coloured box or cylinder (a character: a capsule) sized
## from the shape (`MirrorProxy`); 2D `(x, y)` maps to 3D `(x, 0, y)` at the one scale
## `RenderConfig.unit`, so the sim stays flat and height is visual only. Floors are flat slabs,
## walls full height.
##
## It follows the bodies that move: each frame a moving body's shape transform is read and the proxy
## written only when it changed; a sleeping `RigidBody2D` is not even read, and a wall or any
## body that never moves is written once. A body that spawns later (`SceneTree.node_added`) is
## mirrored on the next frame, once its own `_ready` has built its collision shapes; one that
## despawns (`tree_exiting`) loses its proxies; a collider rebuilt under a body (a hit furniture
## piece's) re-mirrors it; a character who dies is hidden (the ragdoll's mirror is a later job).
##
## A domain's own mesh replaces the proxy per body kind through `builders` (kind -> `Callable`:
## `(body: Node2D) -> Node3D`, a node of the body's own mesh in a local frame where its origin is
## the body's, or null to keep the proxy); the node then follows the body's whole transform instead
## of a shape's, and the kinds are `MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE` and
## `FURNITURE`.

## The mesh hook: kind -> `Callable(body) -> Node3D`. Set before `mirror()`.
var builders: Dictionary = {}
## How many proxies exist, how many moving ones an update read and how many it wrote (the
## numbers the tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _proxies := MirrorProxy.new()
var _root: Node
## Body instance id -> that body's rows (see `MirrorProxy.make`).
var _rows: Dictionary = {}
## The rows that follow a moving body, swap-removed when a body leaves.
var _moving: Array[Dictionary] = []
## Bodies that entered the tree (or lost a collider) since the last update, mirrored next.
var _pending: Dictionary = {}


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(_delta: float) -> void:
	update()


## Mirror everything under `root` now (its floors, then every physics body) and watch it for the
## bodies that spawn later.
func mirror(root: Node) -> void:
	_root = root
	for floor_node: Node in root.get_tree().get_nodes_in_group(&"floors"):
		if root.is_ancestor_of(floor_node):
			_add_floor(floor_node as Node2D)
	for body: Node in root.find_children("*", "PhysicsBody2D", true, false):
		_add_body(body as PhysicsBody2D)
	if not root.get_tree().node_added.is_connected(_on_node_added):
		root.get_tree().node_added.connect(_on_node_added)


## The proxies of `body` (an empty array for a body not mirrored).
func proxies_of(body: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		out.append(row["node"])
	return out


## One frame of following: mirror what spawned, then write the proxy of each moving body whose 2D
## transform changed.
func update() -> void:
	_mirror_pending()
	followed = 0
	written = 0
	var i := 0
	while i < _moving.size():
		var row: Dictionary = _moving[i]
		var shape: Variant = row["shape"]  # untyped: a freed node may not be assigned to a Node2D
		if row.get("gone", false) or not is_instance_valid(shape):
			_retire(row, i)
			continue
		var rigid: Variant = row["rigid"]
		if is_instance_valid(rigid) and (rigid as RigidBody2D).sleeping:
			if row["asleep"]:
				i += 1
				continue
			row["asleep"] = true  # read once more, for the last step it took before it slept
		else:
			row["asleep"] = false
		followed += 1
		var xf: Transform2D = (shape as Node2D).global_transform
		if xf != row["last"]:
			row["last"] = xf
			(row["node"] as Node3D).transform = MirrorProxy.lift(xf, row)
			written += 1
		i += 1


## A moving row whose shape or body is gone leaves the follow list at `index` (swap-removed); a body
## that outlives its shape (a rebuilt collider) is mirrored again.
func _retire(row: Dictionary, index: int) -> void:
	_moving[index] = _moving.back()
	_moving.pop_back()
	var body: Variant = row["body"]
	if not row.get("gone", false) and is_instance_valid(body):
		_pending[(body as Node).get_instance_id()] = body


## Mirror the bodies that spawned (or lost a collider) since the last update.
func _mirror_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for body: Variant in batch:
		if is_instance_valid(body) and (body as Node).is_inside_tree():
			_add_body(body as PhysicsBody2D)


## A node entered the tree: a physics body under the root is mirrored on the next update.
func _on_node_added(node: Node) -> void:
	if node is PhysicsBody2D and _root != null and _root.is_ancestor_of(node):
		_pending[node.get_instance_id()] = node


## Mirror `body`'s shapes (or its kind's own mesh), replacing any proxies it already has.
func _add_body(body: PhysicsBody2D) -> void:
	_drop(body)
	var rows := _rows_of(body)
	if rows.is_empty():
		return
	var moving := body is CharacterBody2D or body is AnimatableBody2D or body is RigidBody2D
	for row in rows:
		add_child(row["node"])
		count += 1
		var xf := (row["shape"] as Node2D).global_transform
		(row["node"] as Node3D).transform = MirrorProxy.lift(xf, row)
		row["last"] = xf
		if moving:
			_moving.append(row)
	_rows[body.get_instance_id()] = rows
	_watch(body)


## The rows `body` is shown by: its kind's own mesh when a builder gives one, else one proxy per
## enabled collision shape.
func _rows_of(body: PhysicsBody2D) -> Array[Dictionary]:
	var kind := MirrorProxy.kind_of(body)
	var rows: Array[Dictionary] = []
	if builders.has(kind):
		var made: Variant = (builders[kind] as Callable).call(body)
		if made is Node3D:
			rows.append(_proxies.own_row(body, made))
			return rows
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled or shape_node.shape == null:
			continue
		var row := _proxies.make(body, kind, shape_node)
		if not row.is_empty():
			rows.append(row)
	return rows


## Mirror a floor as a flat slab; it never moves.
func _add_floor(floor_node: Node2D) -> void:
	var row := _proxies.make_floor(floor_node)
	add_child(row["node"])
	count += 1
	_rows[floor_node.get_instance_id()] = [row]
	_watch(floor_node)


## Drop `body`'s proxies (freed at once, so the count is exact) and its rows.
func _drop(body: Node) -> void:
	var id := body.get_instance_id()
	for row: Dictionary in _rows.get(id, []):
		row["gone"] = true
		var node: Node = row["node"]
		if is_instance_valid(node):
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
		count -= 1
	_rows.erase(id)


## Watch `body` leave the tree and, if it can die, die.
func _watch(body: Node) -> void:
	var leaving := _on_body_exiting.bind(body)
	if not body.tree_exiting.is_connected(leaving):
		body.tree_exiting.connect(leaving)
	if body.has_signal(&"died"):
		var dying := _on_body_died.bind(body)
		if not body.is_connected(&"died", dying):
			body.connect(&"died", dying)


## A mirrored body leaves the tree: its proxies go.
func _on_body_exiting(body: Node) -> void:
	_drop(body)


## A mirrored character died: its proxies are hidden.
func _on_body_died(body: Node) -> void:
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		(row["node"] as Node3D).visible = false
		row["gone"] = true  # no longer followed: the update drops it from the follow list
