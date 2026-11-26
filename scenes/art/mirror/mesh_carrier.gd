class_name MeshCarrier
extends Node3D
## Art domain, the carrier of the bodies' meshes (#194 del2d-b3c, interface 27 and 29): the view
## draws the twins' `World3D`, so every body that has a twin (a wall, a floor, a piece, a door, a
## vehicle, a character) shows by a mesh its domain's builder makes (`builders`: key -> `Callable`
## `(body: Node2D) -> Node3D`, a node of the body's own mesh in a frame whose origin is the body's;
## a floor's in a frame at its corner), hung on the body's twin as its child with no transform of
## its own, so it stands where the twin does and nothing writes it. The keys are the kinds
## `MeshKinds.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`, `FURNITURE` and `FLOOR`, and a finer key for
## one art id (`MeshKinds.furniture_key`, `floor_key`) that wins over its kind. A body no builder
## gives a mesh has none: a box would be read off a 2D shape, and every kind that ships has a
## builder. A body the space gave no twin (a rug or a mat: a non-solid piece, which never moves) has
## its mesh placed where it stands, once, as a child of the carrier.
##
## `TwinSpace` feeds it: `carry(twins)` meshes the bodies that are twinned now and every one the
## space says `twinned` (or `untwinned`) from then on, and a `retwinned` body's meshes move to its
## new twin in the same call (a knocked-down door, a rebuilt piece), so a body is never a frame
## without its mesh. A character's twin never turns (a round cylinder), so its mesh holds the turn
## of the 2D body's own rotation, written only when that changes.
##
## The carrier keeps the shown rules each frame: a mesh is hidden while its body's `visible` is
## off, its character is seated in a vehicle or the player's view does not reach it
## (`MirrorSight`), and marked moving for the shaders (`MeshNodes.moving`). A body that dies has its
## mesh hidden unless the mesh says to stay. A still mesh (no hook, turn or rider, of a body the
## view remembers: `StillRows`) is looked at in full only when the one thing that can change what it
## shows did: nearly every piece of a district is one.
##
## A mesh that changes without its body's transform changing (a limb, a crouch, a wheel's spin) has
## two ways: a `mirror_update(body)` method on the mesh node, called each frame the mesh shows, or
## `remirror(node)` to build it again (a dent, an outfit); a body's signal `reshaped` (a hit piece's
## dents, cut again) builds it again too. A mesh node may also have `on_body_died(body) -> bool`
## (true: stay shown). `mesh-hook.md` says which to use when.

## A builder made `mesh` for the physics body `body` (again when the body's mesh is built again):
## what a domain-blind watcher of the meshes (the wall fade) connects to.
signal built(body: Node, mesh: Node3D)

const StillRows := preload("res://scenes/art/mirror/still_rows.gd")

## The mesh hook: key (a kind, or a finer key) -> `Callable(node) -> Node3D`. Set before `carry()`.
var builders: Dictionary = {}
## How many meshes exist, how many an update looked at and how many it wrote (only a character's
## turn is written: the numbers the tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _root: Node
var _twins: TwinSpace
## Body instance id -> its rows (one per mesh: see `MeshKinds.row_of`, plus `twin` and `turns`).
var _rows: Dictionary = {}
## The rows that need a full look each frame, swap-removed when a body leaves.
var _moving: Array[Dictionary] = []
## The still rows, which need one only when what they show can have changed.
var _still := StillRows.new()
## Bodies whose mesh is to be built (again) on the next update.
var _pending: Dictionary = {}
## What the player's view has seen and what it hides (`MirrorSight`).
var _sight := MirrorSight.new()
## The subtrees the view leaves out (`leave_out`): nothing under one is shown.
var _left_out: Array[Node] = []


func _exit_tree() -> void:
	# a carried mesh stands on a twin that outlives this carrier: it goes, and its row and count
	# with it (a carrier put back in a tree meshes those bodies again by `carry`)
	for id: int in _rows.keys():
		for row: Dictionary in _rows[id]:
			row["gone"] = true
			_still.remove(row)
			if is_instance_valid(row["node"]):
				(row["node"] as Node).queue_free()
			count -= 1
		_rows.erase(id)


func _process(_delta: float) -> void:
	update()


## Carry the meshes of the world under `root`: of the bodies its twin space has now and of every
## one it twins from now on. A world with no twin space shows nothing (no twin to carry on).
func carry(root: Node) -> void:
	_root = root
	_use_twins(TwinSpace.of_world(root))
	if _twins == null:
		return
	for body: Node2D in _twins.bodies():
		_on_twinned(body, TwinSpace.twin_for(body))
	for body: Node2D in _twins.bodies_without_twin():
		_on_untwinned(body)


## Leave `subtree` out of the picture: the meshes of every body under it (and of itself) go now, and
## nothing that is twinned under it later is shown. For a world the view was told of that is no
## longer the one to show (a test that builds its own beside the default arena).
func leave_out(subtree: Node) -> void:
	if not _left_out.has(subtree):
		_left_out.append(subtree)
	for id: int in _rows.keys():
		var rows: Array = _rows[id]
		var body: Variant = (rows[0] as Dictionary).get("body") if not rows.is_empty() else null
		if is_instance_valid(body) and (body == subtree or subtree.is_ancestor_of(body)):
			_drop(body)
	for node: Variant in _pending.values():
		if is_instance_valid(node) and subtree.is_ancestor_of(node):
			_pending.erase(node.get_instance_id())


## The meshes of `body` (an empty array for a body with none).
func proxies_of(body: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		out.append(row["node"])
	return out


## The mesh that shows `body` (a child of its twin), or null for a body with none.
func mesh_of(body: Node) -> Node3D:
	var rows: Array = _rows.get(body.get_instance_id(), [])
	return null if rows.is_empty() else (rows[0] as Dictionary)["node"]


## Build `node`'s mesh again now, the old one freed. For a change of shape (a dent, a crouch, a new
## outfit), not of pose: a pose is `mirror_update`.
func remirror(node: Node2D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	_drop(node)
	_carry(node)


## One frame: carry what was twinned or lost its mesh, then look at each carried mesh that needs it:
## its shown state, a character's turn and the mesh's own update.
func update() -> void:
	_mesh_pending()
	followed = _still.size()
	written = 0
	for row: Dictionary in _still.changed():
		_look(row)
	var i := 0
	while i < _moving.size():
		var row: Dictionary = _moving[i]
		if row.get("gone", false) or not is_instance_valid(row["body"]):  # untyped: may be freed
			_retire(row, i)
			continue
		i += 1
		followed += 1
		if not is_instance_valid(row["node"]):
			_lost(row)  # the mesh went with its twin: built again next update
			continue
		_sync_shown(row)
		if row.get("turns", false):
			_turn(row)
		var hook: Callable = row["update"]
		if hook.is_valid() and row["shown"]:
			hook.call(row["body"])


## The full look at a still row that changed: gone with its body, built again when its mesh was
## lost, else shown as the rules say.
func _look(row: Dictionary) -> void:
	if row.get("gone", false):
		return
	if not is_instance_valid(row["body"]):  # untyped: may be freed
		_free_row(row)
	elif not is_instance_valid(row["node"]):
		_lost(row)
	else:
		_sync_shown(row)
		_still.looked(row)


## Show or hide `row`'s mesh as the rules say (`_shown`) when that changed, and mark the mesh as a
## moving thing (or not) for the player's view when that changed.
func _sync_shown(row: Dictionary) -> void:
	var shown := _shown(row)
	if shown != row["shown"]:
		row["shown"] = shown
		(row["node"] as Node3D).visible = shown
	var moves := MirrorSight.moves(row["body"])
	if moves != row["moving"]:
		row["moving"] = moves
		MeshNodes.moving(row["node"], moves)


## Whether `row`'s mesh shows: its body's own `visible` is on (not `is_visible_in_tree`: the 2D
## World is hidden in 3D), the view reaches it, and it is no character seated in a vehicle.
func _shown(row: Dictionary) -> bool:
	var body: Variant = row["body"]
	if not is_instance_valid(body) or not (body as CanvasItem).visible:
		return false
	if _sight.hides(body as Node2D, row):
		return false
	return not MeshKinds.seated(row)


## A row whose body is gone leaves the look list at `index` (swap-removed); its mesh goes with the
## twin, or at once when the body was freed with no exit signal.
func _retire(row: Dictionary, index: int) -> void:
	_moving[index] = _moving.back()
	_moving.pop_back()
	if not row.get("gone", false):
		_free_row(row)


## A body freed with no exit signal: its mesh and its row go at once.
func _free_row(row: Dictionary) -> void:
	row["gone"] = true
	_still.remove(row)
	var mesh: Variant = row["node"]
	if is_instance_valid(mesh):
		(mesh as Node).queue_free()
	count -= 1
	_rows.erase(row["id"])


## A carried body's mesh went with its twin (freed another way): it is carried again next update.
func _lost(row: Dictionary) -> void:
	var body: Variant = row["body"]
	_drop(body)
	_pending[(body as Node).get_instance_id()] = body


## Carry what is pending (a rebuilt collider, a lost mesh) once the frame's own scripts have run.
func _mesh_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if is_instance_valid(node) and (node as Node).is_inside_tree() and not _is_left_out(node):
			_drop(node)  # built again: the old mesh goes
			_carry(node as Node2D)


## Whether `node` lies under a subtree the view leaves out.
func _is_left_out(node: Node) -> bool:
	for subtree: Node in _left_out:
		if is_instance_valid(subtree) and (node == subtree or subtree.is_ancestor_of(node)):
			return true
	return false


## A body got a twin: its mesh is built on it (a retwin of a carried body is `_on_retwinned`'s).
func _on_twinned(body: Node2D, _twin: Node3D) -> void:
	if (
		_root == null or not _root.is_ancestor_of(body) or _is_left_out(body)
		or _rows.has(body.get_instance_id())
	):
		return
	_carry(body)


## A body the space gave no twin: its mesh is placed where it stands.
func _on_untwinned(body: Node2D) -> void:
	if _root == null or not _root.is_ancestor_of(body) or _is_left_out(body):
		return
	if not _rows.has(body.get_instance_id()):
		_carry(body)


## Show `body` by a mesh carried on its twin when a builder gives its kind one: the mesh is the
## twin's child with no transform of its own. A character's mesh holds the turn of the 2D body. A
## body with no twin has the mesh placed at its pose, a child of the carrier.
func _carry(body: Node2D) -> void:
	if _twins == null:
		return  # no twin space: nothing to carry on
	var twin := TwinSpace.twin_for(body) as Node3D
	if twin == null and _twins.is_waiting(body):
		_pending[body.get_instance_id()] = body  # its twin is still to come: asked again
		return
	if twin != null and twin.get_parent() != _twins:
		return
	var kind := MeshKinds.kind_of(body)
	var builder := builder_for(body)
	var made: Variant = builder.call(body) if builder.is_valid() else null
	if not made is Node3D:
		return
	if kind != MeshKinds.FLOOR:
		built.emit(body, made)
	var row := MeshKinds.row_of(body, made)
	row["twin"] = twin
	row["turns"] = twin != null and kind == MeshKinds.CHARACTER
	row["shown"] = _shown(row)
	(made as Node3D).visible = row["shown"]
	if twin != null:
		twin.add_child(made)
	else:
		add_child(made)
		(made as Node3D).transform = PlanSpace.lift_transform(body.global_transform)
	if row["turns"]:
		_turn(row)
	count += 1
	_file(body, row)
	_rows[body.get_instance_id()] = [row]
	_watch(body)


## File `row` among those looked at each frame, if it needs a look at all: a character, a piece, a
## door or a vehicle (a plan handle in HARD that is no wall), one hidden now or one with an update.
## It is a still one when nothing of it runs each frame (no hook, turn or rider) and its body is
## none the view shows only once it has been seen (`MirrorVisionConfig.seen_first`).
func _file(body: Node2D, row: Dictionary) -> void:
	var hooked := (row["update"] as Callable).is_valid()
	var moving := (
		body.is_in_group(&"characters")
		or body.is_in_group(TwinSpace.PIECES)
		or (body.is_in_group(TwinSpace.HARD) and not body.is_in_group(TwinSpace.WALLS))
	)
	if not (moving or hooked or not row["shown"]):
		return
	var seen_first := MirrorVisionConfig.seen_first.any(
		func(group: StringName) -> bool: return body.is_in_group(group)
	)
	if hooked or row["turns"] or row["rides"] != null or seen_first:
		_moving.append(row)
	else:
		_still.add(row)


## A carried body's twin was replaced (`TwinSpace.retwin`: a knocked-down door's `DoorBody` by a
## `DoorSlab`, a piece's by a new one): the old twin is freed at the frame's end, so each mesh of
## the body moves to the new twin at once, never a frame without it.
func _on_retwinned(body: Node2D, _old: Node3D) -> void:
	var rows: Array = _rows.get(body.get_instance_id(), [])
	if rows.is_empty():
		return
	var twin := TwinSpace.twin_for(body) as Node3D
	if twin == null or twin.get_parent() != _twins:
		_drop(body)
		return
	for row: Dictionary in rows:
		var mesh: Variant = row["node"]
		if is_instance_valid(mesh) and (mesh as Node).get_parent() != twin:
			if (mesh as Node).get_parent() != null:
				(mesh as Node).get_parent().remove_child(mesh)
			twin.add_child(mesh)
		row["twin"] = twin
		if row.get("turns", false):
			_turn(row)  # the new twin holds no turn yet: a character's facing is put on it now


## Turn a carried character's mesh to the 2D body's rotation (its twin does not turn, or turns by
## what the body last gave it): written only when it changed.
func _turn(row: Dictionary) -> void:
	var mesh := row["node"] as Node3D
	var twin := row["twin"] as Node3D
	var want := Basis(Vector3.UP, -(row["body"] as Node2D).global_rotation)
	var local := twin.global_basis.orthonormalized().inverse() * want
	if not local.is_equal_approx(mesh.basis):
		mesh.basis = local
		written += 1


## Take `twins` as the twin space meshes are carried on, and hear of what it twins.
func _use_twins(twins: TwinSpace) -> void:
	if is_instance_valid(_twins) and _twins != twins:
		_twins.twinned.disconnect(_on_twinned)  # pointed at another space: leave the old one
		_twins.untwinned.disconnect(_on_untwinned)
		_twins.retwinned.disconnect(_on_retwinned)
	if twins != null and not twins.twinned.is_connected(_on_twinned):
		twins.twinned.connect(_on_twinned)
		twins.untwinned.connect(_on_untwinned)
		twins.retwinned.connect(_on_retwinned)
	_twins = twins


## The builder of `node`: the one under its finer key (kind and art id), else its kind's; an invalid
## `Callable` for none.
func builder_for(node: Node) -> Callable:
	var kind := MeshKinds.kind_of(node)
	if kind == MeshKinds.FURNITURE or kind == MeshKinds.FLOOR:
		var art := MeshKinds.art_of(node)
		var key := MeshKinds.floor_key(art) if kind == MeshKinds.FLOOR else (
			MeshKinds.furniture_key(art)
		)
		if art != "" and builders.has(key):
			return builders[key]
	return builders.get(kind, Callable())


## Free `body`'s meshes at once (so the count is exact) and forget its rows.
func _drop(body: Node) -> void:
	var id := body.get_instance_id()
	for row: Dictionary in _rows.get(id, []):
		row["gone"] = true
		_still.remove(row)
		var node: Variant = row["node"]  # untyped: a carried mesh goes with its freed twin
		if is_instance_valid(node):
			if (node as Node).get_parent() != null:
				(node as Node).get_parent().remove_child(node)  # a carried mesh leaves its twin
			(node as Node).queue_free()
		count -= 1
	_rows.erase(id)


## Watch `body` leave the tree, say it was `reshaped` (a piece whose dents were cut again) and, if
## it can die, die.
func _watch(body: Node) -> void:
	var leaving := _on_body_exiting.bind(body)
	if not body.tree_exiting.is_connected(leaving):
		body.tree_exiting.connect(leaving)
	if body.has_signal(&"reshaped"):
		var again := _on_reshaped.bind(body)
		if not body.is_connected(&"reshaped", again):
			body.connect(&"reshaped", again)
	if body.has_signal(&"died"):
		var dying := _on_body_died.bind(body)
		if not body.is_connected(&"died", dying):
			body.connect(&"died", dying)


## A carried body's silhouette changed (a piece's dents were cut again): its mesh is built again on
## the next update, as `remirror` does.
func _on_reshaped(body: Node) -> void:
	if is_instance_valid(body):
		_pending[body.get_instance_id()] = body


## A carried body leaves the tree: its meshes go.
func _on_body_exiting(body: Node) -> void:
	_sight.forget(body)
	_drop(body)


## A carried body died: its mesh is hidden and no longer looked at, unless the mesh has an
## `on_body_died(body)` that answers true (a corpse shown by the same mesh, or the ragdoll's
## handover: see `mesh-hook.md`).
func _on_body_died(body: Node) -> void:
	for row: Dictionary in _rows.get(body.get_instance_id(), []):
		var mesh := row["node"] as Node3D
		if mesh.has_method(&"on_body_died") and mesh.call(&"on_body_died", body) == true:
			continue
		mesh.visible = false
		row["gone"] = true  # no longer looked at: the update drops it from the list
		_still.remove(row)
