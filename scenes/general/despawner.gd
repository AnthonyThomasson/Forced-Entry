extends Node
## General domain: autoloaded as `Despawner`. Any system that spawns transient world debris
## (casings, chips) hands the node to `track()`; once the live count passes `max_scene_objects` the
## oldest are freed, so the scene never accumulates debris without bound. Nodes that free themselves
## auto-drop out via their `tree_exited` signal.

## Max number of tracked debris objects allowed at once. Spawning past this frees the oldest.
## Owned here (the despawner is the only thing that reads it).
@export var max_scene_objects: int = 1000

## Node -> its FIFO entry, so arbitrary self-removal is constant time.
var _index: Dictionary = {}
## Oldest entry: { node, prev, next }; empty when nothing is tracked.
var _head: Dictionary = {}
## Newest entry; empty when nothing is tracked.
var _tail: Dictionary = {}


## Register a freshly spawned debris node. Enforces the cap immediately, so the
## oldest are freed the moment a new spawn pushes the count over the limit.
func track(node: Node) -> void:
	var entry := { "node": node, "prev": _tail, "next": {} }
	if _tail.is_empty():
		_head = entry
	else:
		_tail["next"] = entry
	_tail = entry
	_index[node] = entry
	# Drop it from the list if it disappears on its own (avoids stale entries).
	node.tree_exited.connect(_on_object_exited.bind(node))
	_enforce_cap()


## Number of objects currently tracked.
func count() -> int:
	return _index.size()


## Free the oldest tracked nodes until the count is within the cap.
func _enforce_cap() -> void:
	while count() > max_scene_objects:
		var oldest := _take_oldest()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Unlink and return the oldest tracked node.
func _take_oldest() -> Node:
	if _head.is_empty():
		return null
	var entry := _head
	_head = entry["next"]
	if _head.is_empty():
		_tail = {}
	else:
		_head["prev"] = {}
	_index.erase(entry["node"])
	return entry["node"]


## Drop a node from tracking when it leaves the tree. An already evicted node is no longer indexed,
## so its delayed exit cannot remove another object.
func _on_object_exited(node: Node) -> void:
	if not _index.has(node):
		return
	var entry: Dictionary = _index[node]
	var prev: Dictionary = entry["prev"]
	var next: Dictionary = entry["next"]
	if prev.is_empty():
		_head = next
	else:
		prev["next"] = next
	if next.is_empty():
		_tail = prev
	else:
		next["prev"] = prev
	_index.erase(node)
