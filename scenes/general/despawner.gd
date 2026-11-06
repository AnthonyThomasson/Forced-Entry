extends Node
## Autoload (`Despawner`) that caps how many transient bodies (debris, casings, particles, …) live
## in the scene at once. Spawners hand each new node to `track`; once over the cap, the
## oldest are freed, so the scene never accumulates debris without bound. Nodes that free themselves
## auto-drop out via their `tree_exited` signal.

## Max number of tracked debris objects allowed at once. Spawning past this frees the oldest.
## Owned here (the despawner is the only thing that reads it).
@export var max_scene_objects: int = 1000

## Tracked entries oldest first: ticket (a rising number) -> the node's instance id. Godot keeps a
## dictionary in insertion order and unlinks an erased entry in constant time, so the oldest is the
## first key and a node leaving on its own costs no shifting or scan. A freed node's id is kept
## here until its entry is dropped, never the node itself.
var _fifo: Dictionary = {}
## Instance id -> that node's oldest ticket, or an array of tickets (oldest first) when it was
## tracked more than once: each `track` is an entry of its own, as it was in the array this
## replaced.
var _tickets: Dictionary = {}
## The ticket the next `track` takes.
var _next_ticket := 0


## Register a freshly spawned debris node. Enforces the cap immediately, so the
## oldest are freed the moment a new spawn pushes the count over the limit.
func track(node: Node) -> void:
	var id := node.get_instance_id()
	_fifo[_next_ticket] = id
	_add_ticket(id, _next_ticket)
	_next_ticket += 1
	# Drop it from the list if it disappears on its own (avoids stale entries). A node tracked again
	# is connected once: its exit drops one entry, the oldest, as before.
	var exited := _on_object_exited.bind(node)
	if not node.tree_exited.is_connected(exited):
		node.tree_exited.connect(exited)
	_enforce_cap()


## Number of objects currently tracked.
func count() -> int:
	return _fifo.size()


## Free the oldest tracked nodes until the count is within the cap.
func _enforce_cap() -> void:
	while _fifo.size() > maxi(max_scene_objects, 0):
		var oldest := _take_oldest()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Drop the oldest entry and return its node (null when that node is already freed).
func _take_oldest() -> Node:
	var ticket := _first_ticket()
	var id: int = _fifo[ticket]
	_fifo.erase(ticket)
	_drop_first_ticket(id)
	return instance_from_id(id) as Node


## The oldest ticket still held. A dictionary iterates from its oldest key, so this stops at once.
func _first_ticket() -> int:
	for ticket: int in _fifo:
		return ticket
	return -1


## Drop a node from tracking when it leaves the tree: its oldest entry, wherever it lies.
func _on_object_exited(node: Node) -> void:
	var id := node.get_instance_id()
	if not _tickets.has(id):
		return
	_fifo.erase(_drop_first_ticket(id))


## Note that `id` holds `ticket`, newest of its tickets.
func _add_ticket(id: int, ticket: int) -> void:
	var held: Variant = _tickets.get(id)
	if held == null:
		_tickets[id] = ticket
	elif held is Array:
		(held as Array).append(ticket)
	else:
		_tickets[id] = [held, ticket]


## Forget `id`'s oldest ticket and return it.
func _drop_first_ticket(id: int) -> int:
	var held: Variant = _tickets[id]
	if not held is Array:
		_tickets.erase(id)
		return held
	var first: int = (held as Array).pop_front()
	if (held as Array).size() == 1:
		_tickets[id] = (held as Array)[0]
	return first
