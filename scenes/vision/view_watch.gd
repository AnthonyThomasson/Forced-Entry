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
##   from the eye, and the solid's own extent, measured when its shapes come or go and not on the
##   frames it moves in): its transform and collision layer each frame, and by
##   signal its shapes coming and going (a dent or a wall re-cut frees its shape children and adds
##   new ones with no move of the body), its leaving the tree and a door's `changed`; a new solid in
##   the tree is read on the next check. One wholly outside the reach before and after a move, a
##   change or a leave is in no ray, so it forces no rebuild; one that moves into or out of the
##   reach does;
## - no character: a body is looked over whatever the eye's height (`SightRay.top_of`), so it never
##   blocks the cone and its moving costs no rebuild;
## - `VisionConfig.rebuild_every` frames since the last rebuild: the backstop.
##
## A piece's top (and a door's `transparent`) is read once and does not change for its life
## (`ViewShapes`), so it is not watched. Reads the world duck-typed through nodes and signals.
## A frame that rebuilds nothing measures no shape and builds no Array: the key is compared field by
## field and the extents are kept.

const Sector := preload("res://scenes/vision/view_sector.gd")
const SOLID := PhysicsLayers.SOLID
## The fields of `_key`.
const KEY_SIZE := 11

## Whether the cone must be rebuilt now: set by anything that signals a change, cleared by the
## rebuild.
var _dirty := true
## The solids that block sight: instance id -> `[node, transform, collision layer, extent]`, the
## extent being how far (px) its shapes lie from its origin at scale 1.
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


## Start watching `tree`, leaving the bodies in `left_out` (instance ids) out.
func attach(tree: SceneTree, left_out: Array) -> void:
	_tree = tree
	_left_out = left_out
	tree.node_added.connect(_on_node_added)
	for node in tree.root.find_children("*", "CollisionObject2D", true, false):
		_pending.append(node)


## Stop watching: forget everything and let go of the tree.
func detach() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
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


## Whether the world changed since `built`, for a job in flight (`docs/player-vision.md` V1): the
## sight or the cone's tuning is not what it was made from, or a blocker where a ray of the job's
## pose can pass moved, changed, joined or left, or a character blocks (or did, or a blocker moved
## at the last `built`, which a query that frame may have read where it was). The eye and the
## facing are not asked: the job finishes on the pose it started from. The sector stays that of
## the job's pose.
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
		var body: CollisionObject2D = entry[0]
		var now := body.global_transform
		var moved: bool = now != entry[1] or body.collision_layer != entry[2]
		if moved and _moved_within_reach(entry, now):
			_moved_then = true
		entry[1] = now
		entry[2] = body.collision_layer


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


## A node entered the tree: a collider is read at the next check, once it is ready.
func _on_node_added(node: Node) -> void:
	if node is CollisionObject2D:
		_pending.append(node)


## Sort the colliders that entered the tree since the last check; sort them all again when the
## viewer looks over a different height.
func _read_new(see_over: float) -> void:
	if see_over != _see_over:
		_see_over = see_over
		_blockers.clear()
		_known.clear()
		_untwinned.clear()
		_pending.append_array(_tree.root.find_children("*", "CollisionObject2D", true, false))
		_mark()
	for node: Node in _pending:
		if is_instance_valid(node) and node.is_inside_tree():
			_classify(node as CollisionObject2D)
	_pending.clear()
	_sort_again_with_twin()


## Watch `body` as the kind of collider it is.
func _classify(body: CollisionObject2D) -> void:
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
	_blockers[id] = [body, body.global_transform, body.collision_layer, _measure(body)]
	_connect(body, &"child_entered_tree", _changed_shape.bind(body))
	_connect(body, &"child_exiting_tree", _changed_shape.bind(body))
	if body.has_signal(&"changed"):
		_connect(body, &"changed", _mark_near.bind(body))
	_mark_near(body)


## Sort again each collider that was sorted with no twin and has one now.
func _sort_again_with_twin() -> void:
	for id: int in _untwinned.keys():
		var body := _untwinned[id] as CollisionObject2D
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


## A shape came or went on `body`, a blocker: its silhouette changed with no move of its body, and
## its extent is measured again.
func _changed_shape(_child: Node, body: CollisionObject2D) -> void:
	var id := body.get_instance_id()
	if _blockers.has(id):
		(_blockers[id] as Array)[3] = _measure(body)
	_mark_near(body)


## A signal says a blocker changed.
func _mark() -> void:
	_dirty = true


## A signal says the blocker `body` changed: it is a rebuild when `body` is within reach.
func _mark_near(body: CollisionObject2D) -> void:
	var id := body.get_instance_id()
	if _blockers.has(id) and _within_reach(_blockers[id], body.global_transform):
		_dirty = true


## The collider `id` left the tree.
func _left(id: int) -> void:
	_untwinned.erase(id)
	_known.erase(id)
	if _blockers.has(id):
		var entry: Array = _blockers[id]
		var body: CollisionObject2D = entry[0]
		_blockers.erase(id)
		if _moved_within_reach(entry, body.global_transform):
			_mark()


## Whether a blocker within reach moved, turned or changed layer since the last rebuild: within
## reach before the change or after it.
func _blockers_moved() -> bool:
	for id in _blockers:
		var entry: Array = _blockers[id]
		var body: CollisionObject2D = entry[0]
		var then: Transform2D = entry[1]
		if body.global_transform == then and body.collision_layer == entry[2]:
			continue
		if _moved_within_reach(entry, body.global_transform):
			return true
	return false


## Whether the blocker `entry`, moved from the transform it has to `now`, was within reach before
## the move or is after it.
func _moved_within_reach(entry: Array, now: Transform2D) -> bool:
	var then: Transform2D = entry[1]
	return _within_reach(entry, then) or _within_reach(entry, now)


## How many times a blocker's extent has been measured.
func measured() -> int:
	return _measured


## Whether the blocker `entry`, its body placed as `placed` (its origin and scale then), has a part
## where a ray can pass: the rays are `view_distance` long and lie in the cone's sector and the
## bubble round the eye, so a solid wholly beyond the reach, or outside both (`ViewSector`), is in
## none of them.
func _within_reach(entry: Array, placed: Transform2D) -> bool:
	var body: CollisionObject2D = entry[0]
	var scale := placed.get_scale()
	var grow := maxf(absf(scale.x), absf(scale.y))
	var extent: float = entry[3]
	if extent == INF:
		# A shape that was not set when it came may be set since: measured again until it is.
		extent = _measure(body)
		entry[3] = extent
		if extent == INF:
			return true
	return _sector.touches(placed.origin, extent * grow)


## How far (px) any part of `body` lies from its origin at scale 1: its shapes' farthest corner,
## each as the shape is placed and scaled in the body. A shape not set yet could be anything:
## unbounded.
func _measure(body: CollisionObject2D) -> float:
	_measured += 1
	var far := 0.0
	for child in body.get_children():
		if child is CollisionShape2D:
			var shape := child as CollisionShape2D
			if shape.shape == null:
				return INF
			var box := shape.shape.get_rect()
			var s := shape.scale
			var grow := maxf(absf(s.x), absf(s.y))
			far = maxf(
				far,
				shape.position.length() + (box.position.length() + box.size.length()) * grow,
			)
		elif child is CollisionPolygon2D:
			var polygon := child as CollisionPolygon2D
			var s := polygon.scale
			var grow := maxf(absf(s.x), absf(s.y))
			for point in polygon.polygon:
				far = maxf(far, polygon.position.length() + point.length() * grow)
	return far
