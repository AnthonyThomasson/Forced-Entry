class_name TwinSpace
extends Node3D
## General domain, the twin 3D space (#194, D3, `docs/adr/0014-twin-staging-and-plan-space.md`,
## interface 29): a 3D physics space beside the 2D simulation, holding a 3D twin of each solid 2D
## body (walls, floors, furniture, doors, vehicles, characters), each with a real height, kept in
## step with its 2D body every physics frame. The 2D simulation stays the truth and nothing in
## gameplay reads the twins yet; the real-cover jobs move reads onto them (a bullet's 3D ray, a
## fragment, a throw, a sight line), then the bodies themselves flip to 3D one class at a time.
##
## **Where it lives.** The twins are children of this node and join the 3D world of the viewport
## it stands in: the main window's own `World3D`, the 3D counterpart of the 2D space the sim runs
## in, so it exists wherever a match or a test world is staged (`MatchBuilder.stage`), headless
## too, and needs no view. The 3D view (Main's `View3D`) draws in a `SubViewport` of its own world
## today; when the bodies themselves are 3D (the flip's last job) it shares this world instead and
## the meshes attach to the bodies. The 3D engine is Jolt (`project.godot`).
##
## **What builds a twin.** Each domain builds the twin of its own body behind a hook, as the mesh
## hook of the 3D render does: `builders` is a list of `Callable(node: Node2D) -> Node3D`, tried in
## order for each body, the first answer that is a node wins, null (not this domain's body) passes
## on. The node is a `CollisionObject3D` with its collision shapes built in code, in the frame of
## the 2D body's origin (`TwinShapes`, `PlanSpace`); this node places it by the body's transform. A
## plain `StaticBody3D` is a body that never moves, placed once; an `AnimatableBody3D` is followed.
## A twin node may have `twin_update(body: Node2D) -> void`, run each frame after it has followed (a
## character's capsule follows its posture). A body is found when it is in the tree
## under the root `watch` was given (`PhysicsBody2D`s, and each node of a group `track_group`
## names, a floor having no physics body), on the next update after it entered, once its own
## `_ready` has built its collision shapes; a body that leaves the tree loses its twin.
##
## **The update rule.** Once per physics frame, before every body's own `_physics_process`
## (priority `PRIORITY`), after the engine has moved the bodies it moves in its step, each followed
## body's `global_transform` is read and its twin written **only when it changed**; a sleeping
## `RigidBody2D` is read once more as it falls asleep and then taken off the list until its
## `sleeping_state_changed` says it woke (so a sleeping piece costs nothing a frame); a body that
## never moves is written once, when twinned. A twin is on its layer only while its body's
## `collision_layer` is not 0 (a dead character, a door knocked down). So a reader in a frame's
## scripts finds a twin exactly where the engine's step left the 2D body, and a body a script moves
## (a walking character) one frame behind where that script puts it (1/60 s); a twin joins the frame
## after its body does. A kinematic twin written is in the space at once (Jolt, `sync_to_physics`
## off).
##
## **What a reader does.** `space()` / `space_of(node)` is the `PhysicsDirectSpaceState3D` to cast
## into; `owner_of(collider)` maps a hit twin (a result's `collider`) to the 2D body it stands for
## (a bullet then calls the body's `get_surface()`); `twin_of(body)` the other way. Layers:
## `PhysicsLayers.TWIN_*`.

## The physics priority of the update: before every body's own `_physics_process` (a vehicle's is
## -1), so the frame's scripts, a bullet's among them, read twins that stand where the physics step
## left the 2D bodies.
const PRIORITY := -100
## The meta a twin carries: the 2D body it stands for.
const OWNER_META := &"twin_owner"

## The twin hook: `Callable(node: Node2D) -> Node3D`, one per domain's kinds. Set before `watch`.
var builders: Array[Callable] = []
## How many twins exist, how many moving ones an update read and how many it wrote (the numbers
## the tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _root: Node
## The groups whose members are twinned though they are no physics body (the floors).
var _groups: Array[StringName] = []
## Body instance id -> its row `{ id, body, twin, last, rigid, asleep, layer, active, update }`.
var _rows: Dictionary = {}
## The rows that follow a moving body, swap-removed when a body leaves.
var _moving: Array[Dictionary] = []
## Bodies (and, while a group is tracked, any `Node2D`: it joins its group in its own `_ready`)
## that entered the tree since the last update, twinned next.
var _pending: Dictionary = {}


func _init() -> void:
	name = "Twins"
	process_physics_priority = PRIORITY


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _physics_process(_delta: float) -> void:
	update()


## Twin the members of `group` (a node that is no physics body: a floor), as bodies are. Before or
## after `watch`.
func track_group(group: StringName) -> void:
	if _groups.has(group):
		return
	_groups.append(group)
	_scan_group(group)


## Twin everything under `root` now (this node must be in the tree) and watch it for the bodies
## that join later.
func watch(root: Node) -> void:
	_root = root
	for group in _groups:
		_scan_group(group)
	for body: Node in root.find_children("*", "PhysicsBody2D", true, false):
		_pending[body.get_instance_id()] = body
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	update()


## One frame: twin what joined, then follow each moving body (the update rule above).
func update() -> void:
	_twin_pending()
	followed = 0
	written = 0
	var i := 0
	while i < _moving.size():
		var row: Dictionary = _moving[i]
		if row["id"] == 0 or not is_instance_valid(row["body"]):  # untyped: may be freed
			_retire(row, i)
		elif _follow(row):
			i += 1
		else:
			_retire(row, i)  # parked: the row swapped into its place is visited next


## The twin of `body`, or null for a body with none (not twinned yet, or no domain builds one).
func twin_of(body: Node) -> Node3D:
	var row: Dictionary = _rows.get(body.get_instance_id(), {})
	return row.get("twin")


## The 3D direct space the twins are in: cast rays and shapes into it.
func space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


## The twin space a node of the sim (a body, a projectile: any node in the tree) is in: the direct
## state of its viewport's 3D world, the one a `TwinSpace` under that viewport builds into. Null
## for a node outside the tree.
static func space_of(node: Node) -> PhysicsDirectSpaceState3D:
	if not node.is_inside_tree():
		return null
	return node.get_viewport().find_world_3d().direct_space_state


## The 2D body the twin `collider` (a ray or shape result's `collider`) stands for, or null for
## anything else (or a body already freed).
static func owner_of(collider: Object) -> Node2D:
	if collider == null or not is_instance_valid(collider):
		return null
	var found: Variant = collider.get_meta(OWNER_META, null)
	return found as Node2D if is_instance_valid(found) else null


## Mark every node of `group` under the root to be twinned on the next update.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D:
			_pending[node.get_instance_id()] = node


## A node entered the tree: a physics body under the root, or (while a group is tracked) any
## `Node2D`, is looked at on the next update, once its `_ready` has run.
func _on_node_added(node: Node) -> void:
	if node is PhysicsBody2D or (not _groups.is_empty() and node is Node2D):
		if _root.is_ancestor_of(node):
			_pending[node.get_instance_id()] = node


## Twin the bodies and group members that joined since the last update.
func _twin_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if is_instance_valid(node) and (node as Node).is_inside_tree() and _is_candidate(node):
			_twin(node as Node2D)


## Whether `node` is a physics body or a member of a tracked group.
func _is_candidate(node: Node) -> bool:
	if node is PhysicsBody2D:
		return true
	for group in _groups:
		if node.is_in_group(group):
			return true
	return false


## Build `node`'s twin through the first builder that makes one and place it.
func _twin(node: Node2D) -> void:
	var id := node.get_instance_id()
	if _rows.has(id):
		return
	var made: Node3D = null
	for builder in builders:
		var built: Variant = builder.call(node)
		if built is Node3D:
			made = built
			break
	if made == null:
		return
	made.set_meta(OWNER_META, node)
	var xf := node.global_transform
	made.transform = PlanSpace.lift_transform(xf)
	add_child(made)
	var solid := made as CollisionObject3D
	var row := {
		"id": id, "body": node, "twin": made, "last": xf, "asleep": false, "active": true,
		"parked": false,
		"rigid": node if node is RigidBody2D else null,
		"layer": solid.collision_layer if solid != null else 0,
		"update": Callable(made, &"twin_update") if made.has_method(&"twin_update") else Callable(),
	}
	_rows[id] = row
	count += 1
	node.tree_exiting.connect(_on_exiting.bind(node), CONNECT_ONE_SHOT)
	if _moves(node):
		_moving.append(row)
		if node is RigidBody2D:
			(node as RigidBody2D).sleeping_state_changed.connect(_on_sleeping.bind(row))


## Whether `node` can move: a character, a door or any rigid body that is not frozen. A body that
## cannot (a wall, a floor, an anchored piece) is twinned once and never read again.
static func _moves(node: Node2D) -> bool:
	if node is RigidBody2D:
		return not (node as RigidBody2D).freeze
	return node is CharacterBody2D or node is AnimatableBody2D


## Follow one moving row (the update rule): a changed transform is written, the twin's layer follows
## the body's; a rigid body that sleeps is read once more as it falls asleep, then parked (false: it
## leaves the list).
func _follow(row: Dictionary) -> bool:
	var rigid: Variant = row["rigid"]
	if rigid != null and (rigid as RigidBody2D).sleeping:
		if row["asleep"]:
			row["parked"] = true  # off the list until it wakes (`_on_sleeping`)
			return false
		row["asleep"] = true  # read once more, for the last step it took before it slept
	else:
		row["asleep"] = false
	followed += 1
	var body: Node2D = row["body"]
	var twin: Node3D = row["twin"]
	var xf := body.global_transform
	if xf != row["last"]:
		row["last"] = xf
		twin.transform = PlanSpace.lift_transform(xf)
		written += 1
	var solid := twin as CollisionObject3D
	if solid != null:
		var active := true
		if body is CollisionObject2D:
			active = (body as CollisionObject2D).collision_layer != 0
		if active != row["active"]:
			row["active"] = active
			solid.collision_layer = row["layer"] if active else 0
	var hook: Callable = row["update"]
	if hook.is_valid():
		hook.call(body)
	return true


## A moving row whose body is gone, or asleep, leaves the follow list at `index` (swap-removed).
func _retire(row: Dictionary, index: int) -> void:
	_moving[index] = _moving.back()
	_moving.pop_back()
	if row["id"] != 0 and not row["parked"]:
		_drop(row)


## A rigid body's sleep changed: one that wakes while parked goes back on the follow list, so a
## sleeping piece costs nothing a frame.
func _on_sleeping(row: Dictionary) -> void:
	if row["parked"] and row["id"] != 0 and not (row["rigid"] as RigidBody2D).sleeping:
		row["parked"] = false
		row["asleep"] = false
		_moving.append(row)


## `body` is leaving the tree: its twin goes with it.
func _on_exiting(body: Node) -> void:
	var row: Dictionary = _rows.get(body.get_instance_id(), {})
	if not row.is_empty():
		_drop(row)


## Free a row's twin (it is out of every query at once) and forget the row.
func _drop(row: Dictionary) -> void:
	_rows.erase(row["id"])
	row["id"] = 0  # a moving list still holding the row drops it at its next update
	count -= 1
	var twin: Variant = row["twin"]
	if is_instance_valid(twin):
		var solid := twin as CollisionObject3D
		if solid != null:
			solid.collision_layer = 0
		(twin as Node).queue_free()
