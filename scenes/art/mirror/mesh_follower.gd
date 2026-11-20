class_name MeshFollower
extends Node3D
## Art domain, the small follower for drawn things that are no physics body (#194 del2d-b3b,
## interface 27): a floor stencil, a dropped item, a thrown grenade, plain `Node2D`s of a tracked
## group, which no twin carries a mesh for. `track(node, builder)` shows one node by the mesh
## `builder(node)` makes (a `Node3D` in 3D units whose origin is the node's), `track_group(group,
## builder)` every node of a group under the world `follow(root)` is given, those already there and
## each as it joins (taken up on the next update, once its `_ready` has run, as the group is joined
## there). The same `track` / `track_group` the mirror has, so a domain's `register` call changes
## only its target.
##
## The rules are the mirror's for a tracked node: the mesh stands on the node's place, turned by its
## 2D turn (`PlanSpace.lift_transform`), written only when the node's transform changed; it is
## hidden with the node's own `visible` and where the player's view does not reach it
## (`MirrorSight`), and marked moving for the shaders (`MeshNodes.moving`) when the node is a thing
## that moves; its own `mirror_update(node)` runs each frame it shows; it is parked (hidden, not
## followed) while the node is out of the tree and freed with the node; `remirror(node)` builds it
## again. A builder that gives no mesh for a node is not asked again until `remirror` or a reparent.

## The meshes that exist, how many tracked nodes an update read and how many it wrote (what the
## tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _root: Node
## Group name -> the builder of its nodes' meshes.
var _group_builders: Dictionary = {}
## Node instance id -> its row: `node`, `mesh`, `builder`, `last` (the transform written), `shown`,
## `moving`, `update` (the mesh's `mirror_update`, or an invalid callable) and `parked`.
var _rows: Dictionary = {}
var _following: Array[Dictionary] = []
## Nodes that entered the tree since the last update, taken up next.
var _pending: Dictionary = {}
var _sight := MirrorSight.new()
## The subtrees the view leaves out (`leave_out`): nothing under one is shown.
var _left_out: Array[Node] = []


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(_delta: float) -> void:
	update()


## Follow the world under `root`: the nodes of the tracked groups already in it now, the others as
## they join.
func follow(root: Node) -> void:
	_root = root
	for group: StringName in _group_builders:
		_scan_group(group)
	if not root.get_tree().node_added.is_connected(_on_node_added):
		root.get_tree().node_added.connect(_on_node_added)


## Leave `subtree` out: the meshes of the nodes under it go now, and nothing that enters under it
## later is shown (a world the view was told of that is no longer the one to show).
func leave_out(subtree: Node) -> void:
	if not _left_out.has(subtree):
		_left_out.append(subtree)
	for row: Dictionary in _rows.values():
		var node: Variant = row["node"]
		if is_instance_valid(node) and subtree.is_ancestor_of(node):
			_drop(node)
	for node: Variant in _pending.values():
		if is_instance_valid(node) and subtree.is_ancestor_of(node):
			_pending.erase(node.get_instance_id())


## Show `node` (it must be in the tree) by the mesh `builder(node)` makes, in place of any it has.
## Returns the mesh, or null when the builder gave none.
func track(node: Node2D, builder: Callable) -> Node3D:
	var made: Variant = builder.call(node)
	if not made is Node3D:
		return null
	_drop(node)
	_add(node, made, builder)
	return made


## Track every node of `group` under the followed world with `builder`.
func track_group(group: StringName, builder: Callable) -> void:
	_group_builders[group] = builder
	_scan_group(group)


## The mesh that shows `node`, or null for a node not shown.
func mesh_of(node: Node) -> Node3D:
	var row: Dictionary = _rows.get(node.get_instance_id(), {})
	return row.get("mesh")


## Build `node`'s mesh again now, the old one freed (a change of shape: a pose is `mirror_update`);
## a node that joined a tracked group after it entered the tree is taken up by this too.
func remirror(node: Node2D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var row: Dictionary = _rows.get(node.get_instance_id(), {})
	var builder: Variant = row.get("builder")
	_drop(node)
	if builder is Callable:
		track(node, builder)
	else:
		_take_up(node)


## One frame: take up what joined, then follow each shown node: its shown state, its place when it
## changed and the mesh's own update.
func update() -> void:
	_take_pending()
	followed = 0
	written = 0
	var i := 0
	while i < _following.size():
		var row := _following[i]
		var node: Variant = row["node"]  # untyped: it may be freed
		if row.get("gone", false) or not is_instance_valid(node):
			_retire(row, i)
			continue
		i += 1
		if row["parked"]:
			continue
		followed += 1
		_sync(row, node)
		var xf: Transform2D = node.global_transform
		if xf != row["last"]:
			row["last"] = xf
			(row["mesh"] as Node3D).transform = PlanSpace.lift_transform(xf)
			written += 1
		if row["shown"] and (row["update"] as Callable).is_valid():
			(row["update"] as Callable).call(node)


## Show `node` by `made` (built by `builder`) and follow it.
func _add(node: Node2D, made: Node3D, builder: Callable) -> void:
	var row := {
		"node": node, "mesh": made, "builder": builder, "last": node.global_transform,
		"shown": true, "moving": false, "parked": false, "id": node.get_instance_id(),
		"update": Callable(made, &"mirror_update") if made.has_method(&"mirror_update")
		else Callable(),
	}
	add_child(made)
	count += 1
	made.transform = PlanSpace.lift_transform(node.global_transform)
	_sync(row, node, true)
	_following.append(row)
	_rows[node.get_instance_id()] = row
	var leaving := _on_exiting.bind(node)
	if not node.tree_exiting.is_connected(leaving):
		node.tree_exiting.connect(leaving)


## Show or hide `row`'s mesh as the rules say when that changed, and mark it as a moving thing (or
## not) for the player's view when that changed.
func _sync(row: Dictionary, node: Node2D, first := false) -> void:
	var shown := node.visible and not _sight.hides(node, row)
	if shown != row["shown"] or first:
		row["shown"] = shown
		(row["mesh"] as Node3D).visible = shown
	var moves := MirrorSight.moves(node)
	if moves != row["moving"]:
		row["moving"] = moves
		MeshNodes.moving(row["mesh"], moves)


## Queue the nodes of `group` already under the followed world to be taken up.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in _root.get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D:
			_pending[node.get_instance_id()] = node


## A node entered the tree: one parked by an earlier exit is shown again; any other `Node2D` under
## the world is looked at next update (it joins its group in its own `_ready`, after this signal).
func _on_node_added(node: Node) -> void:
	if _root == null or not node is Node2D or not _root.is_ancestor_of(node):
		return
	var row: Dictionary = _rows.get(node.get_instance_id(), {})
	if not row.is_empty() and row["parked"]:
		row["parked"] = false
		(row["mesh"] as Node3D).transform = PlanSpace.lift_transform(
			(node as Node2D).global_transform
		)
		row["last"] = (node as Node2D).global_transform
		_sync(row, node as Node2D, true)
	elif not _group_builders.is_empty():
		_pending[node.get_instance_id()] = node


## Take up the nodes that entered the tree since the last update.
func _take_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if is_instance_valid(node) and (node as Node).is_inside_tree():
			_take_up(node)


## Show `node` by the builder of the tracked group it is in (once: a node shown is left be).
func _take_up(node: Node2D) -> void:
	if _rows.has(node.get_instance_id()) or _is_left_out(node):
		return
	for group: StringName in _group_builders:
		if node.is_in_group(group):
			var builder: Callable = _group_builders[group]
			var made: Variant = builder.call(node)
			if made is Node3D:
				_add(node, made, builder)
				return


## Whether `node` lies under a subtree the view leaves out.
func _is_left_out(node: Node) -> bool:
	for subtree: Node in _left_out:
		if is_instance_valid(subtree) and subtree.is_ancestor_of(node):
			return true
	return false


## A followed node leaves the tree: its mesh is parked (hidden, not followed) in case it is put back
## in, and goes with the node when that is freed.
func _on_exiting(node: Node) -> void:
	var row: Dictionary = _rows.get(node.get_instance_id(), {})
	if row.is_empty():
		return
	if node.is_queued_for_deletion():
		_drop(node)
		return
	row["parked"] = true
	(row["mesh"] as Node3D).visible = false


## Free `node`'s mesh at once (so the count is exact) and forget its row.
func _drop(node: Node) -> void:
	var row: Dictionary = _rows.get(node.get_instance_id(), {})
	if row.is_empty():
		return
	row["gone"] = true
	var mesh: Variant = row["mesh"]
	if is_instance_valid(mesh):
		if (mesh as Node).get_parent() != null:
			(mesh as Node).get_parent().remove_child(mesh)
		(mesh as Node).queue_free()
	count -= 1
	_rows.erase(node.get_instance_id())
	_sight.forget(node)


## A row whose node is freed (with no exit signal seen) or dropped leaves the follow list.
func _retire(row: Dictionary, index: int) -> void:
	_following[index] = _following.back()
	_following.pop_back()
	if row.get("gone", false):
		return
	row["gone"] = true
	var mesh: Variant = row["mesh"]
	if is_instance_valid(mesh):
		(mesh as Node).queue_free()
	count -= 1
	_rows.erase(row["id"])
	_sight.forget_id(row["id"])
