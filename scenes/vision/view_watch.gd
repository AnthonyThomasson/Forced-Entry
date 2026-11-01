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
##   from the eye, and the solid's own extent): its transform and collision layer each frame, and by
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

const SOLID := PhysicsLayers.SOLID

## Whether the cone must be rebuilt now: set by anything that signals a change, cleared by the
## rebuild.
var _dirty := true
## The solids that block sight: instance id -> `[node, transform, collision layer]`.
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
## The eye and the reach (`view_distance`) the last check was made for: what "within reach" means.
var _eye := Vector2.ZERO
var _reach := 0.0


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
	_eye = eye
	_reach = float(sight["view_distance"])
	if _built != _key(eye, facing, sight) or _since >= VisionConfig.rebuild_every:
		return true
	var see_over := float(sight["see_over_coverage"])
	_read_new(see_over)
	if _dirty:
		return true
	return _blocking_now(see_over) or _blocking_then or _blockers_moved()


## The cone was rebuilt for `eye`, `facing` and `sight`: these are the inputs it was made from.
func built(eye: Vector2, facing: Vector2, sight: Dictionary) -> void:
	_since = 0
	_dirty = false
	_built = _key(eye, facing, sight)
	_blocking_then = _blocking_now(float(sight["see_over_coverage"]))
	for id in _blockers:
		var entry: Array = _blockers[id]
		entry[1] = (entry[0] as Node2D).global_transform
		entry[2] = (entry[0] as CollisionObject2D).collision_layer


## What the polygon is a function of, apart from the world.
func _key(eye: Vector2, facing: Vector2, sight: Dictionary) -> Array:
	return [
		eye, facing, sight["fov_degrees"], sight["view_distance"], sight["awareness_radius"],
		sight["see_over_coverage"], VisionConfig.cone_rays, VisionConfig.bubble_rays,
		VisionConfig.corner_offset, VisionConfig.far_depth, VisionConfig.far_bleed,
	]


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
	_blockers[id] = [body, body.global_transform, body.collision_layer]
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


## A shape came or went on `body`, a blocker: its silhouette changed with no move of its body.
func _changed_shape(_child: Node, body: CollisionObject2D) -> void:
	_mark_near(body)


## A signal says a blocker changed.
func _mark() -> void:
	_dirty = true


## A signal says the blocker `body` changed: it is a rebuild when `body` is within reach.
func _mark_near(body: CollisionObject2D) -> void:
	if _within_reach(body, body.global_transform.origin):
		_dirty = true


## The collider `id` left the tree.
func _left(id: int) -> void:
	_known.erase(id)
	_characters.erase(id)
	if _blockers.has(id):
		var entry: Array = _blockers[id]
		var body: CollisionObject2D = entry[0]
		_blockers.erase(id)
		if _within_reach(body, (entry[1] as Transform2D).origin) or _within_reach(
			body,
			body.global_transform.origin,
		):
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
		if _within_reach(body, then.origin) or _within_reach(body, body.global_transform.origin):
			return true
	return false


## Whether `body`, standing at `origin`, has a part within the viewer's reach of the eye: the rays
## are `view_distance` long, so a solid wholly beyond that is in none of them.
func _within_reach(body: CollisionObject2D, origin: Vector2) -> bool:
	return origin.distance_to(_eye) <= _reach + _extent(body)


## How far (px) any part of `body` lies from its origin: its shapes' farthest corner, each as the
## shape is placed and scaled in the body. A shape not set yet could be anything: unbounded.
func _extent(body: CollisionObject2D) -> float:
	var far := 0.0
	for child in body.get_children():
		if child is CollisionShape2D:
			var shape := child as CollisionShape2D
			if shape.shape == null:
				return INF
			var box := shape.shape.get_rect()
			var grow := maxf(shape.scale.x, shape.scale.y)
			far = maxf(
				far,
				shape.position.length() + (box.position.length() + box.size.length()) * grow,
			)
		elif child is CollisionPolygon2D:
			var polygon := child as CollisionPolygon2D
			var grow := maxf(polygon.scale.x, polygon.scale.y)
			for point in polygon.polygon:
				far = maxf(far, polygon.position.length() + point.length() * grow)
	return far * maxf(body.global_scale.x, body.global_scale.y)
