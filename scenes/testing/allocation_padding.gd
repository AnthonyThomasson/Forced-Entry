class_name AllocationPadding extends RefCounted
## Testing domain: the `testing.allocation_padding` switch's allocations. A match's order of events
## must not follow what the process allocated (instance ids step in fixed strides, a physics server
## hands out RIDs in turn), and this proves it: with the switch on, `TestWorld.build` allocates
## `nodes` loose nodes and `bodies` physics bodies, areas and shapes before it builds anything, so
## every id and RID the world then takes is shifted. Its only use is a test that plays a fight with
## and without it and compares the two (`perf/` fight fingerprints, perf.md). `release` frees all of
## it (`TestWorld.restore`).

## Whether `TestWorld.build` pads (the switch's knob).
static var enabled := false
## How many loose nodes to allocate, and how many of each physics RID kind. Odd numbers, so no
## stride of the engine's lines up with them.
static var nodes := 777
static var bodies := 333
## What `fill` holds, until `release`.
static var _held_nodes: Array[Node] = []
static var _held_rids: Array[RID] = []


## Allocate the padding if the switch is on (and none is held yet). The nodes stay out of the tree:
## they shift instance ids and memory without joining the world's children or its events.
static func fill() -> void:
	if not enabled or not _held_nodes.is_empty():
		return
	for i in nodes:
		_held_nodes.append(Node2D.new() if i % 2 == 0 else Node.new())
	for i in bodies:
		_held_rids.append(PhysicsServer2D.body_create())
		_held_rids.append(PhysicsServer2D.area_create())
		_held_rids.append(PhysicsServer2D.rectangle_shape_create())


## Free everything `fill` allocated.
static func release() -> void:
	for node in _held_nodes:
		node.free()
	_held_nodes.clear()
	for rid in _held_rids:
		PhysicsServer2D.free_rid(rid)
	_held_rids.clear()


## How many nodes and physics RIDs are held now.
static func held() -> Dictionary:
	return { "nodes": _held_nodes.size(), "rids": _held_rids.size() }
