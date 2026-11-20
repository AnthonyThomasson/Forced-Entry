class_name TwinSpace
extends SubViewport
## General domain, the twin 3D space (#194, D3, `docs/adr/0014-twin-staging-and-plan-space.md`,
## interface 29): a 3D physics space beside the 2D simulation, holding a 3D twin of each solid 2D
## body (walls, floors, furniture, doors, vehicles, characters), each with a real height, kept in
## step with its plan handle every physics frame, or leading it: a free piece and a character are
## 3D bodies that move and write their handle (the footprint); a door and a vehicle drive theirs, a
## wall is written once. Bullets, sight lines and sweeps read the twins.
##
## **Where it lives.** The twins are children of this node, a `SubViewport` (never drawn) with a
## `World3D` of its own: the 3D counterpart of the 2D space the sim runs in, so it exists wherever a
## match or a test world is staged (`MatchBuilder.stage`), headless too, and needs no view. A space
## of its own matters: Jolt solves contacts in the order of the slots its bodies hold and reuses a
## freed body's slot, so worlds that shared one space (the main window's) gave results that
## depended on what the process ran before. The 3D view (Main's `View3D`) draws this world: its
## picture's viewport takes it as its own once it is told of the world (`of_world`), so the meshes
## and lights stand where the bodies are. The 3D engine is Jolt (`project.godot`).
##
## **What builds a twin.** Each domain builds the twin of its own body behind a hook, as the mesh
## hook of the 3D render does: `builders` is a list of `Callable(node: Node2D) -> Node3D`, tried in
## order for each body, the first answer that is a node wins, null (not this domain's body) passes
## on. The node is a `CollisionObject3D` with its collision shapes built in code, in the frame of
## the 2D body's origin (`TwinShapes`, `PlanSpace`); this node places it by the body's transform. A
## plain `StaticBody3D` is placed once, and written again whenever its body moves (a shoved piece):
## a twin is followed by what its body is, not by what the twin is, and a static body keeps Jolt's
## step free of one more always-active body. A house door is led from 3D (a `DoorBody` its swing
## turns writes the 2D door); a door that falls is given a fresh twin, a free body, by `retwin`. A
## twin node may have
## `twin_update(body: Node2D) -> void`, run each frame after it has followed (a
## character's cylinder follows its posture). A body is found when it is in the tree
## under the root `watch` was given (a member of `BODIES`, and each node of a group `track_group`
## names, a floor having no body), on the next update after it entered, once its own
## `_ready` has built its collision shapes; a body that leaves the tree loses its twin.
##
## **The update rule.** Once per physics frame, before every body's own `_physics_process`
## (priority `PRIORITY`), a body a 3D body leads (a free piece, a character) is written from the 3D
## pose **only when it changed**; a sleeping `RigidBody3D` is read once more as it falls asleep and
## then parked off the list until its `sleeping_state_changed` says it woke, with a slow look
## (`PARK_SPREAD` frames round) for the script that moves a sleeping body without waking it; a
## handle nothing leads (a wall, a floor) is written once, when twinned. A twin is on its layer
## only while its owner says so (a dead character's `twin_update`, a door knocked down). So a
## reader in a frame's scripts finds a rigid body's twin exactly where the engine's step left it;
## a door or a character, which a script moves, is one frame behind where that script puts it
## (1/60 s), and a sleeping body a script teleports up to `PARK_SPREAD` frames; a twin joins the
## frame after its body does. A write is pushed to Jolt at once (`force_update_transform`: a
## `Node3D` would push it only at the frame's end), so a ray after the write meets the new pose.
##
## **What a reader does.** `space()` / `space_of(node)` is the `PhysicsDirectSpaceState3D` to cast
## into; `owner_of(collider)` maps a hit twin (a result's `collider`) to the 2D body it stands for
## (a bullet then calls the body's `get_surface()`); `twin_of(body)` the other way. Layers:
## `PhysicsLayers.TWIN_*`.

## A body's twin was replaced (`retwin`): its 2D body, with the new twin already in place and the
## old one still standing until the frame ends, so a mesh carried on it can be moved to the new in
## the same call (Art's `MeshCarrier`).
signal retwinned(body: Node2D, old: Node3D)
## A body (or a member of a tracked group) got its twin, which stands in the space with its row
## made and its 2D body taken over: what Art's `MeshCarrier` hangs the body's mesh on.
signal twinned(body: Node2D, twin: Node3D)
## A body (or a member of a tracked group) was looked at and no builder gave it a twin (a rug or a
## mat: a non-solid piece, which never moves): what Art's `MeshCarrier` places its mesh for, once.
signal untwinned(body: Node2D)

## The physics priority of the update: before every body's own `_physics_process` (a vehicle's is
## -1), so the frame's scripts, a bullet's among them, read twins that stand where the physics step
## left the 2D bodies.
const PRIORITY := -100
## Overlaps a piece placed over a body is moved clear of, read at once (`_clear_pieces_from`).
const CLEAR_HITS := 8
## The squared size of a rotation's twist about up (its `y` and `w` parts) under which a piece is
## taken to lie on its back, with no heading of its own to read.
const NO_TWIST := 1.0e-4
## How many frames the slow look takes to go round the parked bodies: a sleeping rigid body that a
## script moves without waking it is followed within this many frames.
const PARK_SPREAD := 4
## The group of the plan handles that stand for a body (a `Node2D` root with no engine body of its
## own): a node in it is twinned once its `_ready` has run. Joined in the
## root's `_enter_tree`.
const BODIES := &"plan_bodies"
## The group of the plan handles of walls, doors and vehicles: the bodies no shove turns like a
## piece of furniture (what a blast's or a sight line's "first static body" is). Joined in each
## root's `_enter_tree`.
const HARD := &"hard_bodies"
## The group of the plan handles of pieces of furniture and decor (Objects' `EnvironmentObject`, a
## plain `Node2D`): what a bake's furniture holes, a carrier's moving rows and a vehicle's shoves
## find a piece by. Joined in the piece's `_enter_tree`, beside `BODIES`.
const PIECES := &"pieces"
## The group of the walls (Objects' `Wall`, a plan handle that reports its segments): what a bake, a
## blast and the wall fade find a wall by. Joined in the wall's `_enter_tree`.
const WALLS := &"walls"
## The meta a twin carries: the 2D body it stands for.
const OWNER_META := &"twin_owner"
## The meta a 2D body carries while it has a twin: the twin (`twin_for`).
const TWIN_META := &"twin"

## The twin spaces by the instance id of the `World2D` they stand beside: what `space_in` reads, so
## a reader holding the world its nodes stand in (for its navigation map) finds the 3D space too.
static var _beside: Dictionary = {}

## The twin hook: `Callable(node: Node2D) -> Node3D`, one per domain's kinds. Set before `watch`.
var builders: Array[Callable] = []
## How many twins exist, how many moving ones an update read and how many it wrote (the numbers
## the tests and the perf probes read).
var count := 0
var followed := 0
var written := 0
var _root: Node
## The viewport the sim runs in (the watched root's): a body of a world nested in another viewport
## has a twin space of its own.
var _home: Viewport
## The groups whose members are twinned though they are no physics body (the floors), each with
## the script a member is of (a node that is not of it is not looked at when it enters the tree).
var _groups: Dictionary = {}
## Body instance id -> its row `{ id, body, twin, last, last3, lead, frozen, asleep, parked, listed,
## wake, update }`: `lead` the twin when it is a free 3D body that leads its 2D body
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
## Bodies looked at that got no twin (instance id -> body), for a listener that starts late.
var _bare: Dictionary = {}


func _init() -> void:
	name = "Twins"
	own_world_3d = true
	size = Vector2i(2, 2)
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_physics_priority = PRIORITY
	# the plane a free piece of furniture rests on where no floor slab is (a shove past a room's
	# edge must not drop it out of the world); no ray or sweep asks for its layer
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
	_home = root.get_viewport()
	var beside := root.get_viewport().find_world_2d().get_instance_id()
	if not _beside.has(beside):
		_beside[beside] = []
	if not self in _beside[beside]:
		_beside[beside].append(self)
	for group: StringName in _groups:
		_scan_group(group)
	# the pieces and the characters in tree order (the order their twins are made in is the order
	# Jolt sees them), then the groups
	for body: Node in root.find_children("*", "Node2D", true, false):
		if body.is_in_group(PIECES) or body.is_in_group(&"characters"):
			_pending[body.get_instance_id()] = body
	for body: Node in get_tree().get_nodes_in_group(BODIES):
		if root.is_ancestor_of(body) and body.get_viewport() == _home:
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


## Whether `body` entered the tree and is to be twinned by the next update (it has no twin yet, but
## will have one if a domain builds one): a reader that wants the twin waits a frame.
func is_waiting(body: Node) -> bool:
	return _pending.has(body.get_instance_id())


## The twin of `body`, or null for a body with none (not twinned yet, or no domain builds one).
func twin_of(body: Node) -> Node3D:
	var row: Dictionary = _rows.get(body.get_instance_id(), {})
	return row.get("twin")


## The twin space standing in `world` (a direct child: `MatchBuilder.stage` puts it there), or null
## for a world built by hand with none. The 3D view draws that space's `World3D` (`find_world_3d`).
static func of_world(world: Node) -> TwinSpace:
	for child in world.get_children():
		if child is TwinSpace:
			return child
	return null


## The 3D direct space the twins are in: cast rays and shapes into it.
func space() -> PhysicsDirectSpaceState3D:
	return find_world_3d().direct_space_state


## The 3D space a node of the sim (a body, a projectile: any node in the tree) is in: its world's
## twin space's (`space_in` the world it is in); the viewport's own 3D world where no twin space
## stands beside it (a world built by hand: nothing there blocks a line). Null for a node outside
## the tree.
static func space_of(node: Node) -> PhysicsDirectSpaceState3D:
	if not node.is_inside_tree():
		return null
	var viewport := node.get_viewport()
	var twins := space_in(viewport.find_world_2d())
	return twins if twins != null else viewport.find_world_3d().direct_space_state


## The 3D space of the twins standing beside `world` (the `World2D` the sim's nodes stand in, which
## also holds their navigation map): for a reader that holds that world and no node. Null when no
## twin space stands beside it (a world built by hand, with no twins: nothing blocks a 3D line).
static func space_in(world: World2D) -> PhysicsDirectSpaceState3D:
	var stands: Array = _beside.get(world.get_instance_id(), [])
	for i in range(stands.size() - 1, -1, -1):  # the newest: an older one may be on its way out
		var stand: TwinSpace = stands[i]
		if is_instance_valid(stand) and stand.is_inside_tree():
			return stand.space()
	return null


## Everything `query` meets, `page` hits at a time (each page's colliders left out of the next), so
## a floor slab or a wall segment under a crowd cannot push a body out of a capped answer: the
## results of `intersect_shape`, a body's shapes possibly in part (ask for its owner, not for every
## shape). The query's own `exclude` is kept as it was.
static func intersecting(
	in_space: PhysicsDirectSpaceState3D,
	query: PhysicsShapeQueryParameters3D,
	page := 32,
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kept := query.exclude
	var skipped := kept.duplicate()
	while true:
		query.exclude = skipped
		var got := in_space.intersect_shape(query, page)
		for found: Dictionary in got:
			out.append(found)
			skipped.append(found["rid"])
		if got.size() < page:
			break
	query.exclude = kept
	return out


## The twin of the 2D `body`, or null for a body with none (not twinned yet, or no domain builds
## one): `twin_of` for a reader that holds no `TwinSpace`.
static func twin_for(body: Object) -> Node3D:
	if not body.has_meta(TWIN_META):
		return null
	var found: Variant = body.get_meta(TWIN_META)
	return found as Node3D if is_instance_valid(found) else null


## Twin the 2D `body` again, as its domain's builder now answers: a door that was led by a
## kinematic body (`DoorBody`) is a free one once it is knocked down (`DoorSlab`, #194 doors3d,
## D18). The old twin leaves every query at once and is freed; the new one stands where the 2D body
## does. A body with no twin, or in no twin space, is left as it is.
static func retwin(body: Node2D) -> void:
	var twin := twin_for(body)
	var stand := twin.get_parent() as TwinSpace if twin != null else null
	if stand != null:
		stand._retwin(body)


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


## The 3D body that walks the 2D character `body` (a `CharacterBody3D`, #194 chars3d-a): its twin
## when that is a `CharacterBody3D` with a `walk`, else null. The character moves it, and the 2D
## body is written from it (interface 29).
static func walker_of(body: Object) -> CharacterBody3D:
	if body == null or not is_instance_valid(body) or not body.has_meta(TWIN_META):
		return null
	var found: Variant = body.get_meta(TWIN_META)
	return found if is_instance_valid(found) and found is CharacterBody3D else null


## The plan velocity (px/s) the character `body` really covered last frame. A character is walked
## in the twin space (`walker_of`) by its 3D body and its plan handle is only the footprint, so a
## reader of a pace asks here; a body with no walker is nil.
static func real_velocity_of(body: Object) -> Vector2:
	var lead := walker_of(body)
	if lead != null:
		return lead.call(&"real_velocity")
	return Vector2.ZERO


## The row's 3D rigid body whose sleep it follows, or null for a row that is never asleep.
func _sleeper(row: Dictionary) -> Variant:
	var lead: Variant = row["lead"]
	return lead if lead is RigidBody3D else null


## The 2D body the twin `collider` (a ray or shape result's `collider`) stands for, or null for
## anything else (or a body already freed).
static func owner_of(collider: Object) -> Node2D:
	if collider == null or not is_instance_valid(collider):
		return null
	if not collider.has_meta(OWNER_META):
		return null
	var found: Variant = collider.get_meta(OWNER_META)
	return found as Node2D if is_instance_valid(found) else null


## Drop `body`'s twin and build it again now (`retwin`).
func _retwin(body: Node2D) -> void:
	var row: Dictionary = _rows.get(body.get_instance_id(), {})
	if row.is_empty():
		return
	var leaving := _on_exiting.bind(body)
	if body.tree_exiting.is_connected(leaving):
		body.tree_exiting.disconnect(leaving)
	var old := row["twin"] as Node3D
	_drop(row)
	_twin(body)
	retwinned.emit(body, old)


## Mark every node of `group` under the root to be twinned on the next update.
func _scan_group(group: StringName) -> void:
	if _root == null:
		return
	for node: Node in get_tree().get_nodes_in_group(group):
		if _root.is_ancestor_of(node) and node is Node2D and node.get_viewport() == _home:
			_pending[node.get_instance_id()] = node


## A node entered the tree: a plan handle, or a node of a tracked group's kind, under the root is
## looked at on the next update, once its `_ready` has run.
func _on_node_added(node: Node) -> void:
	if node.is_in_group(BODIES) or _is_kind(node):
		# a world of its own nested under the root (a SubViewport) has a twin space of its own
		if _root.is_ancestor_of(node) and node.get_viewport() == _home:
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
		if lead != null and lead.has_method(&"settle_out"):
			lead.call(&"settle_out")
		else:
			_clear_pieces_from(twin_for(node as Object))


## Move every free piece that overlaps the new twin `twin` (a character's, a vehicle's) clear of it.
func _clear_pieces_from(twin: Node3D) -> void:
	var solid := twin as CollisionObject3D
	var movers := PhysicsLayers.TWIN_VEHICLE | PhysicsLayers.TWIN_CHARACTER
	if solid == null or (solid.collision_layer & movers) == 0:
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
		for found: Dictionary in space().intersect_shape(query, CLEAR_HITS):
			var piece := found["collider"] as Object
			if piece is RigidBody3D and (piece as Object).has_method(&"settle_out"):
				piece.call(&"settle_out")


## The 2D bodies that have a twin now (what a late listener of `twinned` takes up).
func bodies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for row: Dictionary in _rows.values():
		if is_instance_valid(row["body"]):
			out.append(row["body"])
	return out


## The 2D bodies looked at that got no twin (what a late listener of `untwinned` takes up).
func bodies_without_twin() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for id: int in _bare.keys():
		var body: Variant = _bare[id]
		if is_instance_valid(body) and (body as Node).is_inside_tree():
			out.append(body)
		else:
			_bare.erase(id)
	return out


## A body no builder twinned left the tree: it is no longer one of those listed without a twin.
func _on_bare_exiting(node: Node) -> void:
	_bare.erase(node.get_instance_id())


## Whether `node` is a plan handle or a member of a tracked group.
func _is_candidate(node: Node) -> bool:
	if node.is_in_group(BODIES):
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
		_bare[id] = node
		var forget := _on_bare_exiting.bind(node)
		if not node.tree_exiting.is_connected(forget):
			node.tree_exiting.connect(forget, CONNECT_ONE_SHOT)
		untwinned.emit(node)
		return
	made.set_meta(OWNER_META, node)
	node.set_meta(TWIN_META, made)
	var xf := node.global_transform
	made.transform = PlanSpace.lift_transform(xf)
	add_child(made)
	made.force_update_transform()
	# a 3D body that takes the 2D body over is the truth and the 2D body its footprint: a free piece
	# (a `RigidBody3D`), a free door slab (the same) and a character (a `CharacterBody3D`, which
	# also has `follow`); a standing door's `DoorBody` (an `AnimatableBody3D` without `follow`) is
	# no lead: it is driven, and writes its 2D follower itself
	var driven := made is AnimatableBody3D and not made.has_method(&"follow")
	var lead: PhysicsBody3D = null
	if made.has_method(&"take_over") and not driven:
		lead = made as PhysicsBody3D
	var row := _new_row(node, made, lead)
	_rows[id] = row
	count += 1
	node.tree_exiting.connect(_on_exiting.bind(node), CONNECT_ONE_SHOT)
	if lead != null:
		lead.take_over(node)
		row["last"] = node.global_transform
		if lead is RigidBody3D:
			row["wake"] = _on_sleeping.bind(row)
			(lead as RigidBody3D).sleeping_state_changed.connect(row["wake"])
		_moving.append(row)
	elif driven and made.has_method(&"take_over"):
		# a kinematic leader (a standing door): its own script turns it and writes the 2D follower
		# in the one step, so this space has nothing to follow
		made.call(&"take_over", node)
	else:
		_follow_body(row, node)
	twinned.emit(node, made)


## A handle that no 3D body leads or drives is written once, when twinned (a wall, a floor); a piece
## that stays where it is (an anchored or a wall-hung one) is looked at slowly in case a script
## moves it (`_look_at_parked`).
func _follow_body(row: Dictionary, node: Node2D) -> void:
	if node.is_in_group(PIECES):
		row["parked"] = true
		row["listed"] = true
		row["frozen"] = true
		_parked.append(row)


## The row of `node` and its twin `made` (a `lead`, when it is a free 3D body leading `node`).
func _new_row(node: Node2D, made: Node3D, lead: PhysicsBody3D) -> Dictionary:
	var xf := node.global_transform
	return {
		"id": node.get_instance_id(), "body": node, "twin": made, "last": xf,
		"last3": made.global_transform, "lead": lead, "frozen": false, "asleep": false,
		"parked": false, "listed": false, "wake": Callable(),
		"update": Callable(made, &"twin_update") if made.has_method(&"twin_update") else Callable(),
	}


## Follow one moving row (the update rule): a changed transform is written; a rigid body that sleeps
## is read once more as it falls asleep, then parked (false: it leaves the list). A rigid body's
## twin has no hook, so one whose transform has not changed is done after that one comparison.
func _follow(row: Dictionary) -> bool:
	var body: Node2D = row["body"]
	var rigid: Variant = _sleeper(row)
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
	var hook: Callable = row["update"]
	if hook.is_valid():
		hook.call(body)
	return true


## Follow a row whose twin is a free 3D body: the 2D body is its footprint, written from the 3D
## pose when that changed; a 2D body a script has moved (its transform is no longer what was
## written) sends the 3D body there instead (`_adopt`).
func _follow_lead(row: Dictionary) -> void:
	var body: Node2D = row["body"]
	if (row["lead"] as Object).has_method(&"follow"):
		# a lead that moves its own footprint (a character's walk writes it): it only asks to be
		# told of a script's move
		row["lead"].call(&"follow", body)
		var step: Callable = row["update"]
		if step.is_valid():
			step.call(body)
		return
	if body.global_transform != row["last"]:
		_adopt(row)
		return
	var lead := row["lead"] as RigidBody3D
	var pose := lead.global_transform
	if pose == row["last3"]:
		return
	row["last3"] = pose
	body.global_transform = plan_transform(pose, body.global_rotation)
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
## heading it fell with). A piece turned over about a horizontal axis has no twist (the
## quaternion's up and scalar parts both vanish: the angle would be noise), so it keeps `held`, the
## heading it had.
static func plan_transform(pose: Transform3D, held: float) -> Transform2D:
	var q := pose.basis.get_rotation_quaternion()
	var heading := held
	if q.y * q.y + q.w * q.w > NO_TWIST:
		heading = -2.0 * atan2(q.y, q.w)
	return Transform2D(heading, PlanSpace.plan_of(pose.origin))


## Write `xf` (the body's transform) to the row's twin.
func _write(row: Dictionary, xf: Transform2D) -> void:
	row["last"] = xf
	var twin := row["twin"] as Node3D
	twin.transform = PlanSpace.lift_transform(xf)
	twin.force_update_transform()  # a Node3D pushes its transform at the frame's end otherwise
	written += 1


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
		if xf != row["last"]:
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
	var sleeper: Variant = _sleeper(row)
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
	var rigid: Variant = _sleeper(row)
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
