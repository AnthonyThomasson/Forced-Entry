extends RefCounted
## Vision domain: what says the cone must be rebuilt (`docs/player-vision.md` V1, the cost rule).
## The polygon is a function of the eye, the facing, what the eye sees by, `VisionConfig`'s rays
## and the blocking solids in reach: so a physics frame in which none of them differs from the
## last rebuild's is one a fresh rebuild would draw again, and the view holds the polygon it has.
##
## What it watches:
## - the eye, the facing, the sight and the cone's tuning, against the last rebuild's;
## - every solid that blocks sight (a top above the viewer's eye height; a low piece is looked
##   over, it is in no ray, so it needs no watching) within the viewer's reach (`view_distance`
##   from the eye, and the solid's own extent, measured from its twin when the twin is reshaped and
##   not on the frames it moves in): its transform and standing each frame, and by signal its
##   twin reshaped (`segment_rebuilt` of a wall a dent re-cut: its extent is measured again), a
##   piece's `reshaped` (a dent in its look; its twin is not cut, so only a rebuild is marked),
## its leaving the tree and a door's `changed`; a new solid in the tree is read on the next check.
## One
##   wholly outside the reach before and after a move, a change or a leave is in no ray, so it
##   forces no rebuild; one that moves into or out of the reach does;
## - no character: a body is looked over whatever the eye's height (`SightRay.top_of`), so it never
##   blocks the cone and its moving costs no rebuild;
## - `VisionConfig.rebuild_every` frames since the last rebuild: the backstop.
##
## A piece's top (and a door's `transparent`) is read once and does not change for its life
## (`ViewShapes`), so it is not watched. Reads the world duck-typed through nodes and signals.
## A frame that rebuilds nothing measures no shape and builds no Array: the key is compared field by
## field and the extents are kept.

const Sector := preload("res://scenes/vision/view_sector.gd")
## What a plan handle stands as while it stands (a blocker).
const SOLID := 1
## What a plan handle stands as while it lies flat (a fallen door): a marker of its own.
const LYING := 2
## The fields of `_key`.
const KEY_SIZE := 11
## A blocker that moved no more than this (px) from where the job snapshot it is where it was: the
## move of its origin plus its extent's turn. Settling bodies creep 0.0005 to 0.003 px a frame for
## dozens of frames, and each creep restarted the job (the third restart in a row a whole build,
## 8 to 10 ms). The move is measured from the snapshot (`built`), not from the last frame, so
## creeps add up and a held pose never lags the live one by more than this. The engine's own hit
## noise is 0.02 px.
const STILL_PX := 0.05

## Whether the cone must be rebuilt now: set by anything that signals a change, cleared by the
## rebuild.
var _dirty := true
## The solids that block sight: instance id -> `[node, transform, standing, extent, footprint]`, the
## extent being how far (px) its twin's shapes lie from its origin, as the twin stands in its frame.
var _blockers := {}
## Every collider classified (blocker, low or character), by instance id.
var _known := {}
## The colliders sorted before their twin came (a body twins a frame after it joins, so it had no
## height and blocked like a wall): instance id -> body, sorted again when its twin arrives.
var _untwinned := {}
## The colliders that entered the tree since the last check.
var _pending: Array = []
## The instance ids of the bodies that never count (the viewer's own).
var _left_out: Array = []
var _tree: SceneTree
## What the last rebuild was made from.
var _built: Array = []
## Frames since the last rebuild.
var _since := 0
## The eye height (the `see_over`) the solids were sorted by.
var _see_over := -1.0
## Where a ray can pass, for the eye, the facing and the sight the last check was made for: what
## "within reach" means (`_within_reach`).
var _sector := Sector.new()
## Whether a blocker within reach had moved by the last rebuild: a query made in the frame it moved
## may have read it where it was, so the next frame rebuilds too.
var _moved_then := false
## How many times a blocker's extent was measured (a test's read of the cost).
var _measured := 0
## Whether the twin space (`TwinSpace`) twinned or re-twinned a body since the untwinned were last
## asked; with no twin space heard (`_twins`) the untwinned are asked each check.
var _twin_news := true
var _twins: TwinSpace


## Start watching `tree`, leaving the bodies in `left_out` (instance ids) out. Given the `twins` of
## the world, the colliders sorted before their twin came (hundreds: the rugs and mats no builder
## twins never will be) are asked again when it twins a body, not on each check.
func attach(tree: SceneTree, left_out: Array, twins: TwinSpace = null) -> void:
	_tree = tree
	_left_out = left_out
	tree.node_added.connect(_on_node_added)
	_pending.append_array(_colliders())
	if twins != null:
		_twins = twins
		twins.twinned.connect(_on_twin_news)
		twins.retwinned.connect(_on_twin_news)


## Stop watching: forget everything and let go of the tree.
func detach() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	if is_instance_valid(_twins):
		_twins.twinned.disconnect(_on_twin_news)
		_twins.retwinned.disconnect(_on_twin_news)
	_twins = null
	_blockers.clear()
	_known.clear()
	_untwinned.clear()
	_pending.clear()
	_tree = null


## Whether a rebuild is due for an eye at `eye` facing `facing`, seeing by `sight`.
func stale(eye: Vector2, facing: Vector2, sight: Dictionary) -> bool:
	_since += 1
	_sector.look(eye, facing, sight)
	if _since >= VisionConfig.rebuild_every:
		return true
	if not _built_for(eye, facing, sight):
		return true
	_read_new(float(sight["eye_height"]))
	if _dirty:
		return true
	return _moved_then or _blockers_moved()


## Every plan handle (a `Node2D` in `TwinSpace.BODIES`: a wall, a piece, a door, a vehicle, a
## character) in the tree.
func _colliders() -> Array:
	return _tree.get_nodes_in_group(TwinSpace.BODIES)


## What the blocker `entry` stands as, to tell a change of it: `SOLID`, and `LYING` for a fallen
## door that lies flat (its `footprint`, found once in `_classify`).
func _layer_of(entry: Array) -> int:
	var part: Variant = entry[4]
	return LYING if part != null and part.flat else SOLID


## Whether the world changed since `built`, for a job in flight (`docs/player-vision.md` V1): the
## sight or the cone's tuning is not what it was made from, or a blocker where a ray of the job's
## pose can pass moved, changed, joined or left (or one moved at the last `built`, which a query
## that frame may have read where it was). A character is looked over, so it is none. The eye and
## the facing are not asked: the job finishes on the pose it started from. The sector stays that
## of the job's pose.
func world_changed(sight: Dictionary) -> bool:
	_since += 1
	if _built.size() != KEY_SIZE or not _tuned_as_built(sight):
		return true
	_read_new(float(sight["eye_height"]))
	if _dirty:
		return true
	return _moved_then or _blockers_moved()


## Forget what the last job was made from: the next ask is a rebuild (a job dropped half done).
func forget() -> void:
	_built = []


## The next `built` is for a job from `eye` facing `facing` seeing by `sight`: the sector "within
## reach" is of that pose, and the colliders that entered the tree are read first.
func look(eye: Vector2, facing: Vector2, sight: Dictionary) -> void:
	_sector.look(eye, facing, sight)
	_read_new(float(sight["eye_height"]))


## A job was started for `eye`, `facing` and `sight`: these are the inputs it is made from.
func built(eye: Vector2, facing: Vector2, sight: Dictionary) -> void:
	_since = 0
	_dirty = false
	_built = _key(eye, facing, sight)
	_moved_then = false
	for id in _blockers:
		var entry: Array = _blockers[id]
		var body: Node2D = entry[0]
		var now := body.global_transform
		var moved: bool = not _stood(entry, now) or _layer_of(entry) != entry[2]
		if moved and _moved_within_reach(entry, now):
			_moved_then = true
		entry[1] = now
		entry[2] = _layer_of(entry)


## What the polygon is a function of, apart from the world: the order `_built_for` reads.
func _key(eye: Vector2, facing: Vector2, sight: Dictionary) -> Array:
	return [
		eye, facing, sight["fov_degrees"], sight["view_distance"], sight["awareness_radius"],
		sight["eye_height"], VisionConfig.cone_rays, VisionConfig.bubble_rays,
		VisionConfig.corner_offset, VisionConfig.far_depth, VisionConfig.far_bleed,
	]


## Whether the last rebuild was made from this eye, facing and sight, and the cone's tuning as it is
## now: `_key` field by field, so a frame that rebuilds nothing builds no Array.
func _built_for(eye: Vector2, facing: Vector2, sight: Dictionary) -> bool:
	return (
		_built.size() == KEY_SIZE
		and _built[0] == eye
		and _built[1] == facing
		and _tuned_as_built(sight)
	)


## Whether the sight and the cone's tuning are those of the last rebuild (`_key` after the pose).
func _tuned_as_built(sight: Dictionary) -> bool:
	return (
		_built[2] == sight["fov_degrees"]
		and _built[3] == sight["view_distance"]
		and _built[4] == sight["awareness_radius"]
		and _built[5] == sight["eye_height"]
		and _built[6] == VisionConfig.cone_rays
		and _built[7] == VisionConfig.bubble_rays
		and _built[8] == VisionConfig.corner_offset
		and _built[9] == VisionConfig.far_depth
		and _built[10] == VisionConfig.far_bleed
	)


## A node entered the tree: a plan handle is read at the next check, once it is ready.
func _on_node_added(node: Node) -> void:
	if node.is_in_group(TwinSpace.BODIES):
		_pending.append(node)


## Sort the colliders that entered the tree since the last check; sort them all again when the
## viewer looks over a different height.
func _read_new(see_over: float) -> void:
	if see_over != _see_over:
		_see_over = see_over
		_blockers.clear()
		_known.clear()
		_untwinned.clear()
		_pending.append_array(_colliders())
		_mark()
	for node: Node in _pending:
		if is_instance_valid(node) and node.is_inside_tree():
			_classify(node as Node2D)
	_pending.clear()
	_sort_again_with_twin()


## Watch `body` as the kind of collider it is.
func _classify(body: Node2D) -> void:
	var id := body.get_instance_id()
	if _known.has(id) or id in _left_out:
		return
	_known[id] = true
	_connect(body, &"tree_exiting", _left.bind(id))
	var top := SightRay.top_of(body)
	if top == INF:
		_untwinned[id] = body  # no twin yet: a wall's worth until it has one
	if top <= _see_over:
		return  # looked over: a low piece, a pane, a character
	# [node, transform, standing, extent, a handle's footprint part or null]
	var entry: Array = [body, body.global_transform, SOLID, _measure(body), body.get(&"footprint")]
	entry[2] = _layer_of(entry)
	_blockers[id] = entry
	if body.has_signal(&"changed"):
		_connect(body, &"changed", _mark_near.bind(body))
	if body.has_signal(&"reshaped"):  # a piece's dent: its twin keeps its shape
		_connect(body, &"reshaped", _mark_near.bind(body))
	if body.has_signal(&"segment_rebuilt"):  # a wall re-cut by a dent
		_connect(body, &"segment_rebuilt", _changed_shape.bind(body))
	_mark_near(body)


## The twin space twinned a body: the untwinned are asked again at the next check.
func _on_twin_news(_body: Node2D, _twin: Node3D = null) -> void:
	_twin_news = true


## Sort again each collider that was sorted with no twin and has one now.
func _sort_again_with_twin() -> void:
	if is_instance_valid(_twins):
		if not _twin_news:
			return
		_twin_news = false
	for id: int in _untwinned.keys():
		var body := _untwinned[id] as Node2D
		if not is_instance_valid(body):
			_untwinned.erase(id)
		elif TwinSpace.twin_for(body) != null:
			_untwinned.erase(id)
			_known.erase(id)
			_blockers.erase(id)
			_classify(body)
			_mark()


## Connect `body`'s `signal_name` to `callable` unless it is already (a body is sorted again when
## the viewer looks over a different height).
func _connect(body: Object, signal_name: StringName, callable: Callable) -> void:
	if not body.is_connected(signal_name, callable):
		body.connect(signal_name, callable)


## A wall's segment was re-cut (`segment_rebuilt`): its silhouette changed with no move of its
## body, and its extent is measured again. A solid that reached into the view before the cut or
## does after it is a rebuild: its old cut may have been in a ray and its new one not.
func _changed_shape(_changed: Variant, body: Node2D) -> void:
	var id := body.get_instance_id()
	if _blockers.has(id):
		var entry: Array = _blockers[id]
		var was_near := _within_reach(entry, body.global_transform)
		entry[3] = _measure(body)
		if was_near:
			_dirty = true
	_mark_near(body)


## A signal says a blocker changed.
func _mark() -> void:
	_dirty = true


## A signal says the blocker `body` changed: it is a rebuild when `body` is within reach.
func _mark_near(body: Node2D) -> void:
	var id := body.get_instance_id()
	if _blockers.has(id) and _within_reach(_blockers[id], body.global_transform):
		_dirty = true


## The collider `id` left the tree.
func _left(id: int) -> void:
	_untwinned.erase(id)
	_known.erase(id)
	if _blockers.has(id):
		var entry: Array = _blockers[id]
		var body: Node2D = entry[0]
		_blockers.erase(id)
		if _moved_within_reach(entry, body.global_transform):
			_mark()


## Whether a blocker within reach moved, turned or changed layer since the last rebuild: within
## reach before the change or after it.
func _blockers_moved() -> bool:
	for id in _blockers:
		var entry: Array = _blockers[id]
		var body: Node2D = entry[0]
		var now: Transform2D = body.global_transform
		var then: Transform2D = entry[1]
		# The common frame, where nothing moved: no call but the body's own transform.
		if now == then and (entry[4] == null or _layer_of(entry) == entry[2]):
			continue
		if _stood(entry, now) and _layer_of(entry) == entry[2]:
			continue
		if _moved_within_reach(entry, now):
			return true
	return false


## Whether the blocker `entry` is, as `now`, where the job snapshot it (`STILL_PX`).
func _stood(entry: Array, now: Transform2D) -> bool:
	return _lag_of(entry, now) <= STILL_PX


## How far (px) the blocker `entry` as `now` is from the snapshot: its origin's move and the move of
## the farthest point of it by the turn of its axes; unbounded while its extent is.
func _lag_of(entry: Array, now: Transform2D) -> float:
	var then: Transform2D = entry[1]
	if now == then:
		return 0.0
	var extent: float = entry[3]
	if extent == INF:
		return INF
	var turn := maxf((now.x - then.x).length(), (now.y - then.y).length())
	return (now.origin - then.origin).length() + extent * turn


## The most any watched blocker, in reach or not, lags the snapshot (a test's read of the bound).
func lag() -> float:
	var worst := 0.0
	for id in _blockers:
		var entry: Array = _blockers[id]
		worst = maxf(worst, _lag_of(entry, (entry[0] as Node2D).global_transform))
	return worst


## How many watched blockers are off the snapshot but within `STILL_PX` of it: the cone built from
## the snapshot is the live world's only to that (a test's read).
func creeping() -> int:
	var count := 0
	for id in _blockers:
		var entry: Array = _blockers[id]
		var now: Transform2D = (entry[0] as Node2D).global_transform
		count += int(now != entry[1] and _stood(entry, now))
	return count


## Whether the blocker `entry`, moved from the transform it has to `now`, was within reach before
## the move or is after it.
func _moved_within_reach(entry: Array, now: Transform2D) -> bool:
	var then: Transform2D = entry[1]
	return _within_reach(entry, then) or _within_reach(entry, now)


## How many times a blocker's extent has been measured.
func measured() -> int:
	return _measured


## Whether the blocker `entry`, its body placed as `placed` (its origin then), has a part
## where a ray can pass: the rays are `view_distance` long and lie in the cone's sector and the
## bubble round the eye, so a solid wholly beyond the reach, or outside both (`ViewSector`), is in
## none of them.
func _within_reach(entry: Array, placed: Transform2D) -> bool:
	var body: Node2D = entry[0]
	var extent: float = entry[3]
	if extent == INF:
		# A shape that was not set when it came may be set since: measured again until it is.
		extent = _measure(body)
		entry[3] = extent
		if extent == INF:
			return true
	return _sector.touches(placed.origin, extent)


## How far (px) any part of `body` lies from its origin: its twin's shapes' farthest
## corner, as the twin stands in the body's frame; unbounded with no twin (it is measured again once
## it has one).
func _measure(body: Node2D) -> float:
	_measured += 1
	var twin := TwinSpace.twin_for(body) as CollisionObject3D
	if twin == null:
		return INF
	var far := 0.0
	for child in twin.get_children():
		var holder := child as CollisionShape3D
		if holder == null or holder.shape == null:
			continue
		for point in TwinShapes.footprint_of(holder.shape, holder.transform):
			far = maxf(far, point.length())
	return far
