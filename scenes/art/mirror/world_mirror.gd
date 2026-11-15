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
## body that never moves is written once. A body or floor that spawns later
## (`SceneTree.node_added`) is mirrored on the next frame, once its own `_ready` has built its
## collision shapes (a floor has joined the group `floors`); one that despawns (`tree_exiting`)
## loses its proxies; a collision shape added to or removed from a mirrored body (a hit wall's or
## furniture piece's rebuilt collider) re-mirrors that body. A proxy is hidden while its shape is
## disabled (a character seated in a vehicle) or its body's own `visible` is false, and shown again
## when they are not; a character who dies is hidden (the ragdoll's mirror is a later job).
##
## A domain's own mesh replaces the proxy per body kind through `builders` (key -> `Callable`:
## `(body: Node2D) -> Node3D`, a node of the body's own mesh in a local frame where its origin is
## the body's, or null to keep the proxy); the node then follows the body's whole transform instead
## of a shape's. The keys are the kinds `MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`,
## `FURNITURE` and `FLOOR`, and a finer key for one art id (`MirrorProxy.furniture_key`,
## `floor_key`) that wins over its kind. A floor's builder is given the floor and returns its mesh
## in a frame whose origin is the floor's corner. A thing drawn that is no physics body (a dropped
## item, a bullet, debris) is mirrored the same way by `track` (one node) and `track_group` (every
## node of a group, as it joins).

## The mesh hook: key (a kind, or a finer key) -> `Callable(node) -> Node3D`. Set before
## `mirror()`.
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
## Bodies and floors that entered the tree (or gained or lost a collision shape) since the last
## update, mirrored next.
var _pending: Dictionary = {}
## Group name -> the `Callable` that builds the mesh of a node of that group (`track_group`).
var _group_builders: Dictionary = {}


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
		if not _tracked_by_group(body):
			_add_body(body as PhysicsBody2D)
	for group: StringName in _group_builders:
		_scan_group(group)
	if not root.get_tree().node_added.is_connected(_on_node_added):
		root.get_tree().node_added.connect(_on_node_added)


## The proxies of `body` (an empty array for a body not mirrored).
func proxies_of(body: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		out.append(row["node"])
	return out


## Show `node` (a `Node2D` that is no physics body: a dropped item, a bullet) by the mesh
## `builder(node)` makes, a `Node3D` in 3D units in a frame whose origin is the node's, followed
## like a body: written only when the node's transform changed, hidden with the node's `visible`,
## freed when the node leaves the tree. The node must be in the tree. Returns the mesh, or null
## when the builder gave none.
func track(node: Node2D, builder: Callable) -> Node3D:
	var made: Variant = builder.call(node)
	if not made is Node3D:
		return null
	_drop(node)
	_add_tracked(node, made)
	return made


## Track every node of `group` under the mirrored root with `builder`: the ones already there now,
## the others as they join (mirrored on the next frame, once their `_ready` has run, as a body is).
## A node of a tracked group that is a physics body is shown by the builder, not by proxies.
func track_group(group: StringName, builder: Callable) -> void:
	_group_builders[group] = builder
	_scan_group(group)


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
		var shown := _shown(row)
		if shown != row["shown"]:
			row["shown"] = shown
			(row["node"] as Node3D).visible = shown
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


## Mirror the bodies and floors that spawned (or gained or lost a collision shape) since the last
## update. A floor joins its group in its own `_ready`, after it entered the tree: that is checked
## here.
func _mirror_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			continue
		if _tracked_by_group(node):
			continue
		if node is PhysicsBody2D:
			_add_body(node as PhysicsBody2D)
		elif ((node as Node).is_in_group(&"floors")
				and not _rows.has((node as Node).get_instance_id())):
			_add_floor(node as Node2D)


## Queue the nodes of `group` already under the root to be tracked on the next update.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in _root.get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D:
			_pending[node.get_instance_id()] = node


## A node entered the tree: a physics body under the root, or a node that may turn out a floor
## (a `Node2D` with a `size` and a `color`: it joins its group in its own `_ready`), is mirrored on
## the next update.
func _on_node_added(node: Node) -> void:
	if _root == null or not _root.is_ancestor_of(node):
		return
	if (
		node is PhysicsBody2D
		or _may_be_floor(node)
		or (not _group_builders.is_empty() and node is Node2D)
	):
		_pending[node.get_instance_id()] = node


## Whether `node` could be a floor: a `Node2D` that has a `size` and a `color` (read duck-typed, as
## a floor is in the Objects domain).
func _may_be_floor(node: Node) -> bool:
	return node is Node2D and node.get("size") is Vector2 and node.get("color") is Color


## A collision shape came or went under a mirrored body: the body is mirrored again on the next
## update.
func _on_shape_changed(child: Node, body: Node) -> void:
	if child is CollisionShape2D and is_instance_valid(body):
		_pending[body.get_instance_id()] = body


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
		row["shown"] = _shown(row)
		(row["node"] as Node3D).visible = row["shown"]
		# A shape that is off now may come on (a static body's too): that row is read each frame.
		if moving or not row["shown"]:
			_moving.append(row)
	_rows[body.get_instance_id()] = rows
	_watch(body)


## The rows `body` is shown by: its kind's own mesh when a builder gives one, else one proxy per
## collision shape (a disabled one too: it is hidden until it is enabled), not counting a shape on
## its way out.
func _rows_of(body: PhysicsBody2D) -> Array[Dictionary]:
	var kind := MirrorProxy.kind_of(body)
	var rows: Array[Dictionary] = []
	var builder := _builder_for(body, kind)
	if builder.is_valid():
		var made: Variant = builder.call(body)
		if made is Node3D:
			rows.append(_proxies.own_row(body, made))
			return rows
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null or shape_node.is_queued_for_deletion():
			continue
		var row := _proxies.make(body, kind, shape_node)
		if not row.is_empty():
			rows.append(row)
	return rows


## The builder of `node` of `kind`: the one under its finer key (kind and art id), else the kind's;
## an invalid `Callable` for none.
func _builder_for(node: Node, kind: StringName) -> Callable:
	if kind == MirrorProxy.FURNITURE or kind == MirrorProxy.FLOOR:
		var art := MirrorProxy.art_of(node)
		var key := MirrorProxy.floor_key(art) if kind == MirrorProxy.FLOOR else (
			MirrorProxy.furniture_key(art)
		)
		if art != "" and builders.has(key):
			return builders[key]
	return builders.get(kind, Callable())


## Mirror a floor: its kind's own mesh when a builder gives one (in a frame at the floor's corner),
## else a flat slab; it never moves.
func _add_floor(floor_node: Node2D) -> void:
	var row := {}
	var builder := _builder_for(floor_node, MirrorProxy.FLOOR)
	if builder.is_valid():
		var made: Variant = builder.call(floor_node)
		if made is Node3D:
			row = _proxies.own_row(floor_node, made)
			(made as Node3D).transform = MirrorProxy.lift(floor_node.global_transform, row)
	if row.is_empty():
		row = _proxies.make_floor(floor_node)
	add_child(row["node"])
	count += 1
	_rows[floor_node.get_instance_id()] = [row]
	_watch(floor_node)


## Whether `node` is of a tracked group (`track_group`): it is then shown by that group's builder.
## Returns true once it is tracked (or the builder gave none and the node is left to its proxies).
func _tracked_by_group(node: Node) -> bool:
	if _group_builders.is_empty() or not node is Node2D:
		return false
	var rows: Array = _rows.get(node.get_instance_id(), [])
	if not rows.is_empty() and (rows[0] as Dictionary).get("tracked", false):
		return true  # already shown by its group's builder: not built twice
	for group: StringName in _group_builders:
		if node.is_in_group(group):
			var made: Variant = (_group_builders[group] as Callable).call(node)
			if made is Node3D:
				_drop(node)
				_add_tracked(node as Node2D, made)
				return true
	return false


## Show `node` by `made` and follow it like a moving body.
func _add_tracked(node: Node2D, made: Node3D) -> void:
	var row := _proxies.own_row(node, made)
	row["tracked"] = true
	add_child(made)
	count += 1
	var xf := node.global_transform
	made.transform = MirrorProxy.lift(xf, row)
	row["last"] = xf
	row["shown"] = _shown(row)
	made.visible = row["shown"]
	_moving.append(row)
	_rows[node.get_instance_id()] = [row]
	_watch(node, false)


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


## Whether `row`'s proxy shows: its collision shape is enabled and its body's own `visible` is on
## (not `is_visible_in_tree`: the 2D World is hidden in 3D). A mesh of a domain's own follows the
## body, which has no shape to be disabled.
func _shown(row: Dictionary) -> bool:
	var shape: Variant = row["shape"]
	var body: Variant = row["body"]
	if not is_instance_valid(shape) or not is_instance_valid(body):
		return false
	if shape is CollisionShape2D and (shape as CollisionShape2D).disabled:
		return false
	return (body as CanvasItem).visible


## Watch `body` leave the tree, gain or lose a collision shape (`shapes`: not for a node that is
## shown by a mesh of its own) and, if it can die, die.
func _watch(body: Node, shapes := true) -> void:
	var leaving := _on_body_exiting.bind(body)
	if not body.tree_exiting.is_connected(leaving):
		body.tree_exiting.connect(leaving)
	var changed := _on_shape_changed.bind(body)
	if shapes and not body.child_entered_tree.is_connected(changed):
		body.child_entered_tree.connect(changed)
		body.child_exiting_tree.connect(changed)
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
