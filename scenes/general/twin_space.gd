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
## plain `StaticBody3D` is placed once, and written again whenever its body moves (a shoved piece, a
## swinging door): a twin is followed by what its body is, not by what the twin is, and a static
## body keeps Jolt's step free of one more always-active body. A twin node may have
## `twin_update(body: Node2D) -> void`, run each frame after it has followed (a
## character's cylinder follows its posture). A body is found when it is in the tree
## under the root `watch` was given (`PhysicsBody2D`s, and each node of a group `track_group`
## names, a floor having no physics body), on the next update after it entered, once its own
## `_ready` has built its collision shapes; a body that leaves the tree loses its twin.
##
## **The update rule.** Once per physics frame, before every body's own `_physics_process`
## (priority `PRIORITY`), after the engine has moved the bodies it moves in its step, each followed
## body's `global_transform` is read and its twin written **only when it changed**; a sleeping
## `RigidBody2D` is read once more as it falls asleep and then parked off the list until its
## `sleeping_state_changed` says it woke, with a slow look (`PARK_SPREAD` frames round) for the
## script that moves a sleeping body without waking it; a body that never moves (a wall, a floor, a
## frozen body: not followed, even if it is later unfrozen) is written once, when twinned. A twin
## is on its layer only while its body's `collision_layer` is not 0 (a dead character, a door
## knocked down); a rigid body's layer is read when it moves. So a reader in a frame's scripts
## finds a rigid body's twin exactly where the engine's step left it; a door or a character, which
## a script moves, is one frame behind where that script puts it (1/60 s), and a sleeping body a
## script teleports up to `PARK_SPREAD` frames; a twin joins the frame after its body does. A
## write is pushed to Jolt at once (`force_update_transform`: a `Node3D` would push it only at the
## frame's end), so a ray after the write meets the new pose.
##
## **What a reader does.** `space()` / `space_of(node)` is the `PhysicsDirectSpaceState3D` to cast
## into; `owner_of(collider)` maps a hit twin (a result's `collider`) to the 2D body it stands for
## (a bullet then calls the body's `get_surface()`); `twin_of(body)` the other way. Layers:
## `PhysicsLayers.TWIN_*`.

## The physics priority of the update: before every body's own `_physics_process` (a vehicle's is
## -1), so the frame's scripts, a bullet's among them, read twins that stand where the physics step
## left the 2D bodies.
const PRIORITY := -100
## How many frames the slow look takes to go round the parked bodies: a sleeping rigid body that a
## script moves without waking it is followed within this many frames.
const PARK_SPREAD := 4
## The meta a twin carries: the 2D body it stands for.
const OWNER_META := &"twin_owner"
## The meta a 2D body carries while it has a twin: the twin (`twin_for`).
const TWIN_META := &"twin"

## The twin spaces by the 2D direct space state (its instance id) of the world they stand beside:
## what `space_for` reads, so a reader holding the 2D space the sim casts in finds the 3D one.
static var _beside: Dictionary = {}

## The twin hook: `Callable(node: Node2D) -> Node3D`, one per domain's kinds. Set before `watch`.
var builders: Array[Callable] = []
## How many twins exist, how many moving ones an update read and how many it wrote (the numbers
## the tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _root: Node
## The groups whose members are twinned though they are no physics body (the floors), each with
## the script a member is of (a node that is not of it is not looked at when it enters the tree).
var _groups: Dictionary = {}
## Body instance id -> its row `{ id, body, twin, last, last3, lead, rigid, asleep, parked, listed,
## wake, layer, active, update }`: `lead` the twin when it is a free 3D body that leads its 2D body
## (furniture), `last3` the pose of it last read, `last` the 2D body's transform last written (or
## read).
var _rows: Dictionary = {}
## The rows that follow a moving body, swap-removed when a body leaves.
var _moving: Array[Dictionary] = []
## The rows of sleeping rigid bodies (parked), looked at slowly, and where the look is.
var _parked: Array[Dictionary] = []
var _look := 0
## Bodies (and members of a tracked group's kind: they join their group in their own `_ready`) that
## entered the tree since the last update, twinned next.
var _pending: Dictionary = {}


func _init() -> void:
	name = "Twins"
	process_physics_priority = PRIORITY
	# the plane a free piece of furniture rests on where no floor slab is (a shove past a room's
	# edge
	# must not drop it out of the world); no ray or sweep asks for its layer
	var ground := StaticBody3D.new()
	ground.name = "TwinGround"
	ground.collision_layer = PhysicsLayers.TWIN_GROUND
	ground.collision_mask = 0
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	ground.add_child(plane)
	add_child(ground)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for id: int in _beside.keys():
		var stands: Array = _beside[id]
		stands.erase(self)
		if stands.is_empty():
			_beside.erase(id)


func _physics_process(_delta: float) -> void:
	update()


## Twin the members of `group` (a node that is no physics body: a floor), as bodies are. `kind` is
## the script its members are of: only a node of it is looked at when it enters the tree (no kind:
## any `Node2D` is, which costs a look at every node that joins). Before or after `watch`.
func track_group(group: StringName, kind: Script = null) -> void:
	if _groups.has(group):
		return
	_groups[group] = kind
	_scan_group(group)


## Twin everything under `root` now (this node must be in the tree) and watch it for the bodies
## that join later.
func watch(root: Node) -> void:
	_root = root
	var beside := root.get_viewport().find_world_2d().direct_space_state.get_instance_id()
	if not _beside.has(beside):
		_beside[beside] = []
	if not self in _beside[beside]:
		_beside[beside].append(self)
	for group: StringName in _groups:
		_scan_group(group)
	for body: Node in root.find_children("*", "PhysicsBody2D", true, false):
		_pending[body.get_instance_id()] = body
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	update()


## One frame: twin what joined, then follow each moving body (the update rule above).
func update() -> void:
	_twin_pending()
	_look_at_parked()
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


## The 3D space of the twins standing beside the 2D direct `space` (the one the sim casts in): the
## bridge a reader that still holds a 2D space uses to cast a 3D ray (`SightRay`), until the 2D
## space is gone (ADR 0014). Null when no twin space stands beside it (a world built by hand, with
## no twins: nothing there blocks a 3D line).
static func space_for(space2d: PhysicsDirectSpaceState2D) -> PhysicsDirectSpaceState3D:
	var stands: Array = _beside.get(space2d.get_instance_id(), [])
	for stand: TwinSpace in stands:
		if is_instance_valid(stand) and stand.is_inside_tree():
			return stand.space()
	return null


## The twin of the 2D `body`, or null for a body with none (not twinned yet, or no domain builds
## one): `twin_of` for a reader that holds no `TwinSpace`.
static func twin_for(body: Object) -> Node3D:
	if not body.has_meta(TWIN_META):
		return null
	var found: Variant = body.get_meta(TWIN_META)
	return found as Node3D if is_instance_valid(found) else null


## Let the twins of `a` and `b` share space (`shared`) or collide again: what the 2D bodies'
## collision exception between them does for the 3D bodies, so a character put onto or under a
## piece (a bed it lies on or hides under) does not shove the piece's free 3D body out of the way. A
## body with no twin yet is passed over.
static func share_space(a: Object, b: Object, shared: bool) -> void:
	var first := twin_for(a) as PhysicsBody3D
	var second := twin_for(b) as PhysicsBody3D
	if first == null or second == null:
		return
	if shared:
		first.add_collision_exception_with(second)
	else:
		first.remove_collision_exception_with(second)


## The free 3D body that is the truth of the 2D `body` (furniture, #194 furn3d): its twin when that
## is a `RigidBody3D` with a `push`, else null. A pusher shoves such a piece through it
## (`Knockback.push`).
static func leader_of(body: Object) -> RigidBody3D:
	if body == null or not is_instance_valid(body) or not body.has_meta(TWIN_META):
		return null
	var found: Variant = body.get_meta(TWIN_META)
	if is_instance_valid(found) and found is RigidBody3D and (found as Object).has_method(&"push"):
		return found
	return null


## The 2D body the twin `collider` (a ray or shape result's `collider`) stands for, or null for
## anything else (or a body already freed).
static func owner_of(collider: Object) -> Node2D:
	if collider == null or not is_instance_valid(collider):
		return null
	if not collider.has_meta(OWNER_META):
		return null
	var found: Variant = collider.get_meta(OWNER_META)
	return found as Node2D if is_instance_valid(found) else null


## Mark every node of `group` under the root to be twinned on the next update.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D and node.get_viewport() == get_viewport():
			_pending[node.get_instance_id()] = node


## A node entered the tree: a physics body, or a node of a tracked group's kind, under the root is
## looked at on the next update, once its `_ready` has run.
func _on_node_added(node: Node) -> void:
	if node is PhysicsBody2D or _is_kind(node):
		# a world of its own nested under the root (a SubViewport) has a twin space of its own
		if _root.is_ancestor_of(node) and node.get_viewport() == get_viewport():
			_pending[node.get_instance_id()] = node


## Whether `node` is of the kind (script) of a tracked group (any `Node2D` for a group with no
## kind).
func _is_kind(node: Node) -> bool:
	for group: StringName in _groups:
		var kind: Script = _groups[group]
		if is_instance_of(node, kind) if kind != null else node is Node2D:
			return true
	return false


## Twin the bodies and group members that joined since the last update.
func _twin_pending() -> void:
	if _pending.is_empty():
		return
	var batch := _pending.values()
	_pending = {}
	for node: Variant in batch:
		if is_instance_valid(node) and (node as Node).is_inside_tree() and _is_candidate(node):
			_twin(node as Node2D)
	# a free piece that was placed overlapping a wall or another piece, or that a body spawned on,
	# is moved clear of it, as the 2D engine moved a rigid body clear in its first step, now every
	# twin of the batch is in the space
	for node: Variant in batch:
		if not is_instance_valid(node):
			continue
		var lead := leader_of(node as Object)
		if lead != null:
			lead.call(&"settle_out")
		else:
			_clear_pieces_from(twin_for(node as Object))


## Move every free piece that overlaps the new twin `twin` (a character's, a vehicle's) clear of it.
func _clear_pieces_from(twin: Node3D) -> void:
	var solid := twin as CollisionObject3D
	var bodies := PhysicsLayers.TWIN_VEHICLE | PhysicsLayers.TWIN_CHARACTER
	if solid == null or (solid.collision_layer & bodies) == 0:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = PhysicsLayers.TWIN_WORLD
	query.exclude = [solid.get_rid()]
	for child in solid.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		query.shape = holder.shape
		query.transform = holder.global_transform
		for found: Dictionary in space().intersect_shape(query, 8):
			var piece := found["collider"] as Object
			if piece is RigidBody3D and (piece as Object).has_method(&"settle_out"):
				piece.call(&"settle_out")


## Whether `node` is a physics body or a member of a tracked group.
func _is_candidate(node: Node) -> bool:
	if node is PhysicsBody2D:
		return true
	for group: StringName in _groups:
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
	node.set_meta(TWIN_META, made)
	var xf := node.global_transform
	made.transform = PlanSpace.lift_transform(xf)
	add_child(made)
	made.force_update_transform()
	# a free 3D body that takes the 2D body over (furniture): it is the truth, the 2D body its
	# footprint
	var lead: RigidBody3D = made as RigidBody3D if made.has_method(&"take_over") else null
	var row := _new_row(node, made, lead)
	_rows[id] = row
	count += 1
	node.tree_exiting.connect(_on_exiting.bind(node), CONNECT_ONE_SHOT)
	if lead != null:
		lead.take_over(node)
		row["last"] = node.global_transform
		row["wake"] = _on_sleeping.bind(row)
		lead.sleeping_state_changed.connect(row["wake"])
		_moving.append(row)
		return
	var rigid: Variant = row["rigid"]
	if rigid != null:
		row["wake"] = _on_sleeping.bind(row)
		(rigid as RigidBody2D).sleeping_state_changed.connect(row["wake"])
	if _moves(node):
		_moving.append(row)
	elif rigid != null:
		# frozen now: looked at slowly, in case it is unfrozen later (`_look_at_parked`)
		row["parked"] = true
		row["listed"] = true
		row["frozen"] = true
		_parked.append(row)


## The row of `node` and its twin `made` (a `lead`, when it is a free 3D body leading `node`).
func _new_row(node: Node2D, made: Node3D, lead: RigidBody3D) -> Dictionary:
	var solid := made as CollisionObject3D
	var xf := node.global_transform
	return {
		"id": node.get_instance_id(), "body": node, "twin": made, "last": xf,
		"last3": made.global_transform, "lead": lead, "frozen": false, "asleep": false,
		"active": true, "parked": false, "listed": false, "wake": Callable(),
		"rigid": node if node is RigidBody2D and lead == null else null,
		"layer": solid.collision_layer if solid != null else 0,
		"update": Callable(made, &"twin_update") if made.has_method(&"twin_update") else Callable(),
	}


## Whether `node` can move: a character, a door or any rigid body that is not frozen. A body that
## cannot (a wall, a floor) is twinned once and never read again; a frozen rigid body (an anchored
## piece) is looked at slowly in case it is unfrozen (`_look_at_parked`).
static func _moves(node: Node2D) -> bool:
	if node is RigidBody2D:
		return not (node as RigidBody2D).freeze
	return node is CharacterBody2D or node is AnimatableBody2D


## Follow one moving row (the update rule): a changed transform is written, the twin's layer follows
## the body's; a rigid body that sleeps is read once more as it falls asleep, then parked (false: it
## leaves the list). A rigid body's twin has no hook and its layer is read only as it moves, so one
## whose transform has not changed is done after that one comparison.
func _follow(row: Dictionary) -> bool:
	var body: Node2D = row["body"]
	var rigid: Variant = row["lead"] if row["lead"] != null else row["rigid"]
	if rigid != null:
		if rigid.sleeping:
			if row["asleep"]:
				row["parked"] = true  # off the list until it wakes (`_on_sleeping`)
				if not row["listed"]:
					row["listed"] = true
					_parked.append(row)
				return false
			row["asleep"] = true  # read once more, for the last step it took before it slept
		else:
			row["asleep"] = false
	followed += 1
	if row["lead"] != null:
		_follow_lead(row)
		return true
	var xf := body.global_transform
	var moved: bool = xf != row["last"]
	if not moved and rigid != null:
		return true
	if moved:
		_write(row, xf)
	_sync_layer(row, body)
	var hook: Callable = row["update"]
	if hook.is_valid():
		hook.call(body)
	return true


## Follow a row whose twin is a free 3D body: the 2D body is its footprint, written from the 3D
## pose when that changed; a 2D body a script has moved (its transform is no longer what was
## written) sends the 3D body there instead (`_adopt`).
func _follow_lead(row: Dictionary) -> void:
	var body: Node2D = row["body"]
	var rigid := body as RigidBody2D
	if rigid != null and not rigid.freeze:
		# a footprint is never free: its 3D body moves it, the 2D solver does not
		rigid.freeze = true
	if body.global_transform != row["last"]:
		_adopt(row)
		return
	var lead := row["lead"] as RigidBody3D
	var pose := lead.global_transform
	if pose == row["last3"]:
		return
	row["last3"] = pose
	body.global_transform = _plan_of(pose)
	# as the node reports it: a script's move is told by a change
	row["last"] = body.global_transform
	written += 1
	var hook: Callable = row["update"]
	if hook.is_valid():
		hook.call(body)


## A script moved the 2D body of a row led by a 3D body: the 3D body is put where it stands now,
## upright and at rest, and woken to settle.
func _adopt(row: Dictionary) -> void:
	var body: Node2D = row["body"]
	var lead := row["lead"] as RigidBody3D
	row["last"] = body.global_transform
	lead.global_transform = PlanSpace.lift_transform(row["last"])
	lead.linear_velocity = Vector3.ZERO
	lead.angular_velocity = Vector3.ZERO
	lead.sleeping = false
	lead.force_update_transform()
	row["last3"] = lead.global_transform
	var hook: Callable = row["update"]
	if hook.is_valid():
		hook.call(body)


## The 2D transform under the 3D pose `pose` of a free body: its origin's plan point and its turn
## about up (the twist of its rotation about the up axis, so a piece lying on its side keeps the
## heading it fell with).
static func _plan_of(pose: Transform3D) -> Transform2D:
	var q := pose.basis.get_rotation_quaternion()
	return Transform2D(-2.0 * atan2(q.y, q.w), PlanSpace.plan_of(pose.origin))


## Write `xf` (the body's transform) to the row's twin.
func _write(row: Dictionary, xf: Transform2D) -> void:
	row["last"] = xf
	var twin := row["twin"] as Node3D
	twin.transform = PlanSpace.lift_transform(xf)
	twin.force_update_transform()  # a Node3D pushes its transform at the frame's end otherwise
	written += 1


## The twin is on its layer only while its body's own `collision_layer` is not 0.
func _sync_layer(row: Dictionary, body: Node2D) -> void:
	var solid := row["twin"] as CollisionObject3D
	if solid == null or not body is CollisionObject2D:
		return
	var active := (body as CollisionObject2D).collision_layer != 0
	if active != row["active"]:
		row["active"] = active
		solid.collision_layer = row["layer"] if active else 0


## A slice (`1 / PARK_SPREAD`) of the parked rows is looked at each frame: one whose body has been
## moved by a script (a sleeping piece placed elsewhere) is written, and one that is awake after
## all goes back on the follow list.
func _look_at_parked() -> void:
	if _parked.is_empty():
		return
	var take := ceili(float(_parked.size()) / PARK_SPREAD)
	for _n in take:
		if _parked.is_empty():
			return
		_look %= _parked.size()
		var row := _parked[_look]
		if row["id"] == 0 or not row["parked"] or not is_instance_valid(row["body"]):
			row["listed"] = false  # gone, or woken since: off this list
			_parked[_look] = _parked.back()
			_parked.pop_back()
			continue
		_look += 1
		var xf := (row["body"] as Node2D).global_transform
		var rigid: Variant = row["rigid"]
		if rigid != null and not (rigid as RigidBody2D).freeze and row["frozen"]:
			row["frozen"] = false  # unfrozen: followed from now on
			_wake(row)
		elif xf != row["last"]:
			if row["lead"] != null:
				_adopt(row)
			else:
				_write(row, xf)
			_wake(row)


## A moving row whose body is gone, or asleep, leaves the follow list at `index` (swap-removed).
func _retire(row: Dictionary, index: int) -> void:
	_moving[index] = _moving.back()
	_moving.pop_back()
	if row["id"] != 0 and not row["parked"]:
		_drop(row)


## A rigid body's sleep changed: one that wakes while parked goes back on the follow list, so a
## sleeping piece costs nothing a frame.
func _on_sleeping(row: Dictionary) -> void:
	var sleeper: Variant = row["lead"] if row["lead"] != null else row["rigid"]
	if row["parked"] and row["id"] != 0 and not row["frozen"] and not sleeper.sleeping:
		_wake(row)


## Put a parked row back on the follow list.
func _wake(row: Dictionary) -> void:
	if row["parked"]:
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
	var wake: Callable = row["wake"]
	var rigid: Variant = row["lead"] if row["lead"] != null else row["rigid"]
	if wake.is_valid() and is_instance_valid(rigid):
		var changed: Signal = rigid.sleeping_state_changed
		if changed.is_connected(wake):
			changed.disconnect(wake)  # a body that comes back is twinned, and watched, anew
	var twin: Variant = row["twin"]
	if is_instance_valid(row["body"]):
		(row["body"] as Node).remove_meta(TWIN_META)
	if is_instance_valid(twin):
		var solid := twin as CollisionObject3D
		if solid != null:
			solid.collision_layer = 0
		(twin as Node).queue_free()
