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
## when they are not (a mesh of a domain's own, every shape of its body disabled); a body that dies
## has its mesh hidden unless the mesh says to stay.
##
## A domain's own mesh replaces the proxy per body kind through `builders` (key -> `Callable`:
## `(body: Node2D) -> Node3D`, a node of the body's own mesh in a local frame where its origin is
## the body's, or null to keep the proxy); the node then follows the body's whole transform instead
## of a shape's. The keys are the kinds `MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`,
## `FURNITURE` and `FLOOR`, and a finer key for one art id (`MirrorProxy.furniture_key`,
## `floor_key`) that wins over its kind. A floor's builder is given the floor and returns its mesh
## in a frame whose origin is the floor's corner. A thing drawn that is no physics body (a dropped
## item, a bullet, debris) is mirrored the same way by `track` (one node) and `track_group` (every
## node of a group that was in it when it entered the tree).
##
## A mesh that changes without its body's transform changing (a limb, a crouch, a wheel's spin, a
## dent) has two ways: a `mirror_update(body)` method on the mesh node, called each frame the mesh
## shows, or `remirror(node)` to build it again. A mesh node may also have `on_body_died(body) ->
## bool` (true: stay shown and keep following). `mesh-hook.md` says which to use when.

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


## Build `node`'s mesh again now, the old one freed: a body's, a floor's or a tracked node's
## (through the builder it was tracked with). For a change of shape (a dent, a crouch, a new
## outfit), not of pose: a pose is `mirror_update`. A node that joined a tracked group after it
## entered the tree is taken up by this too.
func remirror(node: Node2D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var rows: Array = _rows.get(node.get_instance_id(), [])
	var builder: Variant = null if rows.is_empty() else (rows[0] as Dictionary).get("builder")
	_drop(node)
	if builder is Callable:
		track(node, builder)
	else:
		_mirror_node(node)


## Show `node` (a `Node2D` that is no physics body: a dropped item, a bullet) by the mesh
## `builder(node)` makes, a `Node3D` in 3D units in a frame whose origin is the node's, followed
## like a body: written only when the node's transform changed, hidden with the node's `visible`,
## freed when the node is (it survives a reparent: out of the tree its mesh is hidden). The node
## must be in the tree. Returns the mesh, or null when the builder gave none.
func track(node: Node2D, builder: Callable) -> Node3D:
	var made: Variant = builder.call(node)
	if not made is Node3D:
		return null
	_drop(node)
	_add_tracked(node, made, builder)
	return made


## Track every node of `group` under the mirrored root with `builder`: the ones already there now,
## the others as they join (mirrored on the next frame, once their `_ready` has run, as a body is).
## A node joins by being in the group once its `_ready` has run (a group joined in `_ready` counts,
## one
## joined later is taken up by `remirror(node)`). A node
## of a tracked group that is a physics body is shown by the builder, not by proxies; a builder that
## returns null for a node leaves a physics body its proxies and any other node unshown (it is not
## asked again until `remirror`, a body's rebuilt collider or a reparent).
func track_group(group: StringName, builder: Callable) -> void:
	_group_builders[group] = builder
	_scan_group(group)


## One frame of following: mirror what spawned, then follow each moving body: write its mesh when
## its 2D transform changed and run the mesh's `mirror_update` while it shows.
func update() -> void:
	_mirror_pending()
	followed = 0
	written = 0
	var i := 0
	while i < _moving.size():
		var row: Dictionary = _moving[i]
		if row.get("gone", false) or not is_instance_valid(row["shape"]):  # untyped: may be freed
			_retire(row, i)
			continue
		i += 1
		if not row.get("parked", false):
			_follow(row)


## Follow one moving row: its shown state and transform, then the mesh's own update. A sleeping
## `RigidBody2D` is not read (once more as it falls asleep): only a mesh that updates itself is
## looked at, for whether it still shows.
func _follow(row: Dictionary) -> void:
	var rigid: Variant = row["rigid"]
	if is_instance_valid(rigid) and (rigid as RigidBody2D).sleeping:
		if row["asleep"]:
			if (row["update"] as Callable).is_valid():
				_sync_shown(row)
				_run_update(row)
			return
		row["asleep"] = true  # read once more, for the last step it took before it slept
	else:
		row["asleep"] = false
	followed += 1
	_sync_shown(row)
	var xf: Transform2D = (row["shape"] as Node2D).global_transform
	if xf != row["last"]:
		row["last"] = xf
		(row["node"] as Node3D).transform = MirrorProxy.lift(xf, row)
		written += 1
	_run_update(row)


## Show or hide `row`'s mesh as the rules say (`_shown`) when that changed.
func _sync_shown(row: Dictionary) -> void:
	var shown := _shown(row)
	if shown != row["shown"]:
		row["shown"] = shown
		(row["node"] as Node3D).visible = shown


## Run a shown mesh's `mirror_update(body)` (a row of a mesh that has none holds no callable).
func _run_update(row: Dictionary) -> void:
	var hook: Callable = row["update"]
	if hook.is_valid() and row["shown"]:
		hook.call(row["body"])


## A moving row whose shape or body is gone leaves the follow list at `index` (swap-removed); a body
## that outlives its shape (a rebuilt collider) is mirrored again; a body freed with no exit signal
## (out of the tree) takes its mesh with it.
func _retire(row: Dictionary, index: int) -> void:
	_moving[index] = _moving.back()
	_moving.pop_back()
	if row.get("gone", false):
		return
	var body: Variant = row["body"]
	if is_instance_valid(body):
		_pending[(body as Node).get_instance_id()] = body
		return
	row["gone"] = true
	var mesh: Node = row["node"]
	if is_instance_valid(mesh):
		mesh.queue_free()
	count -= 1
	_rows.erase(row["id"])


## Mirror the bodies and floors that spawned (or gained or lost a collision shape) since the last
## update. A floor joins its group in its own `_ready`, after it entered the tree: that is checked
## here.
func _mirror_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if is_instance_valid(node) and (node as Node).is_inside_tree():
			_mirror_node(node)


## Mirror `node` as what it is: shown by its group's builder, a body's mesh or proxies, or a floor
## (one already shown by a builder of a tracked group stays so).
func _mirror_node(node: Node) -> void:
	if _is_tracked(node) or _tracked_by_group(node):
		return
	if node is PhysicsBody2D:
		_add_body(node as PhysicsBody2D)
	elif node.is_in_group(&"floors") and not _rows.has(node.get_instance_id()):
		_add_floor(node as Node2D)


## Queue the nodes of `group` already under the root to be tracked on the next update.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in _root.get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D:
			_pending[node.get_instance_id()] = node


## A node entered the tree. One parked by an earlier exit (a tracked node reparented) shows again; a
## physics body under the root, a node that may turn out a floor (a `Node2D` with a `size` and a
## `color`) and, while a group is tracked, any `Node2D` (it joins its group in its own `_ready`,
## after this signal) are mirrored on the next update, once their `_ready` has run. A node that is
## none of these, or already shown, is not queued.
func _on_node_added(node: Node) -> void:
	if _root == null or not _root.is_ancestor_of(node):
		return
	var rows: Array = _rows.get(node.get_instance_id(), [])
	if not rows.is_empty() and (rows[0] as Dictionary).get("parked", false):
		for row: Dictionary in rows:
			_unpark(row)
	elif (
		node is PhysicsBody2D
		or _may_be_floor(node)
		or (not _group_builders.is_empty() and node is Node2D)
	):
		_pending[node.get_instance_id()] = node


## A parked row's node is back in the tree: its mesh is placed where the node is and shown by the
## usual rules.
func _unpark(row: Dictionary) -> void:
	row["parked"] = false
	var xf := (row["shape"] as Node2D).global_transform
	var mesh := row["node"] as Node3D
	mesh.transform = MirrorProxy.lift(xf, row)
	row["last"] = xf
	row["shown"] = _shown(row)
	mesh.visible = row["shown"]


## Whether `node` could be a floor: a `Node2D` that has a `size` and a `color` (read duck-typed, as
## a floor is in the Objects domain).
func _may_be_floor(node: Node) -> bool:
	return node is Node2D and node.get("size") is Vector2 and node.get("color") is Color


## A collision shape came or went under a mirrored body: the body is mirrored again on the next
## update (unless the shape is queued to be freed, or its mesh follows the shapes itself).
func _on_shape_changed(child: Node, body: Node) -> void:
	if not child is CollisionShape2D or not is_instance_valid(body):
		return
	if child.is_queued_for_deletion() or _mesh_follows_shapes(body):
		return  # a shape on its way out is no change: its replacement already came in
	_pending[body.get_instance_id()] = body


## Whether `body` is shown by a mesh that follows its collision shapes itself (a method
## `follows_shapes() -> true`: a wall's, which meshes the one segment that was rebuilt), so the
## mirror does not build it again.
func _mesh_follows_shapes(body: Node) -> bool:
	var rows: Array = _rows.get(body.get_instance_id(), [])
	if rows.size() != 1:
		return false
	var mesh: Variant = (rows[0] as Dictionary).get("node")
	return (
		is_instance_valid(mesh)
		and (mesh as Object).has_method(&"follows_shapes")
		and (mesh as Object).call(&"follows_shapes") == true
	)


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
		row["id"] = body.get_instance_id()
		var xf := (row["shape"] as Node2D).global_transform
		(row["node"] as Node3D).transform = MirrorProxy.lift(xf, row)
		row["last"] = xf
		row["shown"] = _shown(row)
		(row["node"] as Node3D).visible = row["shown"]
		# A shape that is off now may come on (a static body's too): that row is read each frame,
		# as is one whose mesh updates itself.
		if moving or not row["shown"] or (row["update"] as Callable).is_valid():
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


## Whether `node` is now shown by the builder of a tracked group it is in (true once it is; a
## builder that gives none leaves the node to its proxies).
func _tracked_by_group(node: Node) -> bool:
	if _group_builders.is_empty() or not node is Node2D:
		return false
	for group: StringName in _group_builders:
		if node.is_in_group(group):
			var builder: Callable = _group_builders[group]
			var made: Variant = builder.call(node)
			if made is Node3D:
				_drop(node)
				_add_tracked(node as Node2D, made, builder)
				return true
	return false


## Whether `node` is already shown by a builder (a tracked node: not built twice).
func _is_tracked(node: Node) -> bool:
	var rows: Array = _rows.get(node.get_instance_id(), [])
	return not rows.is_empty() and (rows[0] as Dictionary).get("tracked", false)


## Show `node` by `made` (built by `builder`, which `remirror` calls again) and follow it like a
## moving body.
func _add_tracked(node: Node2D, made: Node3D, builder: Callable) -> void:
	var row := _proxies.own_row(node, made)
	row["tracked"] = true
	row["builder"] = builder
	row["id"] = node.get_instance_id()
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
## body, which has no shape of its row's: it shows unless the body has shapes and every one is
## disabled.
func _shown(row: Dictionary) -> bool:
	var shape: Variant = row["shape"]
	var body: Variant = row["body"]
	if not is_instance_valid(shape) or not is_instance_valid(body):
		return false
	if shape is CollisionShape2D and (shape as CollisionShape2D).disabled:
		return false
	if not (body as CanvasItem).visible:
		return false
	return not MirrorProxy.shapes_all_off(row)


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


## A mirrored body leaves the tree: its proxies go; a tracked node's mesh is parked (hidden, not
## followed) in case it is reparented, and goes when the node is freed.
func _on_body_exiting(body: Node) -> void:
	var rows: Array = _rows.get(body.get_instance_id(), [])
	if rows.is_empty() or body.is_queued_for_deletion() or not _is_tracked(body):
		_drop(body)
		return
	for row: Dictionary in rows:
		row["parked"] = true
		(row["node"] as Node3D).visible = false


## A mirrored body died: its mesh is hidden and no longer followed, unless the mesh has an
## `on_body_died(body)` that answers true (a corpse shown by the same mesh, or the ragdoll's
## handover: see `mesh-hook.md`).
func _on_body_died(body: Node) -> void:
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		var mesh := row["node"] as Node3D
		if mesh.has_method(&"on_body_died") and mesh.call(&"on_body_died", body) == true:
			continue
		mesh.visible = false
		row["gone"] = true  # no longer followed: the update drops it from the follow list
