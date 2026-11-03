extends RefCounted
## Vision domain: what says the cone must be rebuilt (`docs/player-vision.md` V1, the cost rule).
## The polygon is a function of the eye, the facing, what the eye sees by, `VisionConfig`'s rays
## and the blocking solids in reach: so a physics frame in which none of them differs from the
## last rebuild's is one a fresh rebuild would draw again, and the view holds the polygon it has.
##
## What it watches:
## - the eye, the facing, the sight and the cone's tuning, against the last rebuild's;
## - every solid that blocks sight (coverage above the viewer's `see_over`; a low piece is looked
##   over, it is in no ray, so it needs no watching) within the viewer's reach (`view_distance`
##   from the eye, and the solid's own extent, measured when its shapes come or go and not on the
##   frames it moves in): its transform and collision layer each frame, and by
##   signal its shapes coming and going (a dent or a wall re-cut frees its shape children and adds
##   new ones with no move of the body), its leaving the tree and a door's `changed`; a new solid in
##   the tree is read on the next check. One wholly outside the reach before and after a move, a
##   change or a leave is in no ray, so it forces no rebuild; one that moves into or out of the
##   reach does;
## - the characters: one blocks while its posture covers more than the viewer looks over, and then
##   it may move, turn its shape off or die in any frame, so the cone is rebuilt every frame it
##   does (and the frame after the last stops). No character does at the default sight;
## - `VisionConfig.rebuild_every` frames since the last rebuild: the backstop.
##
## A piece's coverage (and a door's `transparent`) is read once and does not change for its life
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
## The characters in the tree, by instance id (the nodes).
var _characters := {}
## Every collider classified (blocker, low or character), by instance id.
var _known := {}
## The colliders that entered the tree since the last check.
var _pending: Array = []
## The rids that never count (the viewer's own body).
var _left_out: Array = []
var _tree: SceneTree
## What the last rebuild was made from.
var _built: Array = []
## Frames since the last rebuild.
var _since := 0
## Whether a character blocked sight at the last rebuild.
var _blocking_then := false
## The `see_over` the solids were sorted by.
var _see_over := -1.0
## Where a ray can pass, for the eye, the facing and the sight the last check was made for: what
## "within reach" means (`_within_reach`).
var _sector := Sector.new()
## Whether a blocker within reach had moved by the last rebuild: a query made in the frame it moved
## may have read it where it was, so the next frame rebuilds too.
var _moved_then := false
## How many times a blocker's extent was measured (a test's read of the cost).
var _measured := 0


## Start watching `tree`, leaving the bodies in `left_out` (rids) out.
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
	_characters.clear()
	_known.clear()
	_pending.clear()
	_tree = null


## Whether a rebuild is due for an eye at `eye` facing `facing`, seeing by `sight`.
func stale(eye: Vector2, facing: Vector2, sight: Dictionary) -> bool:
	_since += 1
	_sector.look(eye, facing, sight)
	if _since >= VisionConfig.rebuild_every or not _built_for(eye, facing, sight):
		return true
	var see_over := float(sight["see_over_coverage"])
	_read_new(see_over)
	if _dirty:
		return true
	return _blocking_now(see_over) or _blocking_then or _moved_then or _blockers_moved()


## The cone was rebuilt for `eye`, `facing` and `sight`: these are the inputs it was made from.
func built(eye: Vector2, facing: Vector2, sight: Dictionary) -> void:
	_since = 0
	_dirty = false
	_built = _key(eye, facing, sight)
	_blocking_then = _blocking_now(float(sight["see_over_coverage"]))
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
		sight["see_over_coverage"], VisionConfig.cone_rays, VisionConfig.bubble_rays,
		VisionConfig.corner_offset, VisionConfig.far_depth, VisionConfig.far_bleed,
	]


## Whether the last rebuild was made from this eye, facing and sight, and the cone's tuning as it is
## now: `_key` field by field, so a frame that rebuilds nothing builds no Array.
func _built_for(eye: Vector2, facing: Vector2, sight: Dictionary) -> bool:
	return (
		_built.size() == KEY_SIZE
		and _built[0] == eye
		and _built[1] == facing
		and _built[2] == sight["fov_degrees"]
		and _built[3] == sight["view_distance"]
		and _built[4] == sight["awareness_radius"]
		and _built[5] == sight["see_over_coverage"]
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
		_characters.clear()
		_known.clear()
		_pending.append_array(_tree.root.find_children("*", "CollisionObject2D", true, false))
		_mark()
	for node: Node in _pending:
		if is_instance_valid(node) and node.is_inside_tree():
			_classify(node as CollisionObject2D)
	_pending.clear()


## Watch `body` as the kind of collider it is.
func _classify(body: CollisionObject2D) -> void:
	var id := body.get_instance_id()
	if _known.has(id) or body.get_rid() in _left_out:
		return
	_known[id] = true
	_connect(body, &"tree_exiting", _left.bind(id))
	if body is CharacterBody2D:
		_characters[id] = body
		return
	if SightRay.coverage_of(body) <= _see_over:
		return
	_blockers[id] = [body, body.global_transform, body.collision_layer, _measure(body)]
	_connect(body, &"child_entered_tree", _changed_shape.bind(body))
	_connect(body, &"child_exiting_tree", _changed_shape.bind(body))
	if body.has_signal(&"changed"):
		_connect(body, &"changed", _mark_near.bind(body))
	_mark_near(body)


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
	if _blockers.has(id) and _within_reach(_blockers[id], body.global_transform.origin):
		_dirty = true


## The collider `id` left the tree.
func _left(id: int) -> void:
	_known.erase(id)
	_characters.erase(id)
	if _blockers.has(id):
		var entry: Array = _blockers[id]
		var body: CollisionObject2D = entry[0]
		_blockers.erase(id)
		if _moved_within_reach(entry, body.global_transform):
			_mark()


## Whether a character blocks sight now.
func _blocking_now(see_over: float) -> bool:
	for id in _characters:
		var body: CollisionObject2D = _characters[id]
		if body.collision_layer & SOLID != 0 and SightRay.coverage_of(body) > see_over:
			return true
	return false


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
	return _within_reach(entry, then.origin) or _within_reach(entry, now.origin)


## How many times a blocker's extent has been measured.
func measured() -> int:
	return _measured


## Whether the blocker `entry`, its body standing at `origin`, has a part where a ray can pass: the
## rays are `view_distance` long and lie in the cone's sector and the bubble round the eye, so a
## solid wholly beyond the reach, or outside both (`ViewSector`), is in none of them.
func _within_reach(entry: Array, origin: Vector2) -> bool:
	var body: CollisionObject2D = entry[0]
	var scale := body.global_scale
	var grow := maxf(absf(scale.x), absf(scale.y))
	var extent: float = entry[3]
	if extent == INF:
		# A shape that was not set when it came may be set since: measured again until it is.
		extent = _measure(body)
		entry[3] = extent
		if extent == INF:
			return true
	return _sector.touches(origin, extent * grow)


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
