class_name MeshPool
extends RefCounted
## Art domain, the mesh kit's pool of a batch's parts (interface 12): the places of one
## `MeshNodes.batch` that short-lived things (a tracer, a casing) take and give back, so no node,
## mesh or place is made while the game runs. The parts in use are the first `count` places, all
## drawn: a part that leaves is replaced by the last one, which keeps its own frame, so the batch
## never has a hole. A frame is in 3D units in the batch's parent (`MeshNodes.part_frame` makes one
## from px). The frames are also kept here, readable (`frame_at`), because the batch's own copy is
## the renderer's.

## The batch (a `MultiMeshInstance3D`, `MeshNodes.batch`): the owner of the pool adds it to the
## world.
var node: MultiMeshInstance3D
## How many places are in use.
var count := 0
## The owner of each place (an instance id), and each place's frame.
var _owners: Array[int] = []
var _frames: Array[Transform3D] = []
## An owner's instance id -> its place.
var _slots := {}


func _init(batch: MultiMeshInstance3D) -> void:
	node = batch
	_owners.resize(capacity())
	_frames.resize(capacity())


## How many parts the batch holds at most.
func capacity() -> int:
	return node.multimesh.instance_count


## The next place for `owner` (its own when it already has one), or -1 when the batch is full.
func add(owner: Object) -> int:
	var id := owner.get_instance_id()
	if _slots.has(id):
		return _slots[id]
	if count >= capacity():
		return -1
	var slot := count
	count += 1
	_owners[slot] = id
	_slots[id] = slot
	_frames[slot] = Transform3D()
	MeshNodes.batch_show(node, count)
	return slot


## `owner`'s place gives way to the last one (nothing for an owner with none).
func remove(owner: Object) -> void:
	var id := owner.get_instance_id()
	if not _slots.has(id):
		return
	var slot: int = _slots[id]
	var last := count - 1
	_slots.erase(id)
	if slot != last:
		_owners[slot] = _owners[last]
		_slots[_owners[slot]] = slot
		place(slot, _frames[last])
	count = last
	MeshNodes.batch_show(node, count)


## Put the part in `slot` at `frame`.
func place(slot: int, frame: Transform3D) -> void:
	_frames[slot] = frame
	node.multimesh.set_instance_transform(slot, frame)


## The frame of the part in `slot`.
func frame_at(slot: int) -> Transform3D:
	return _frames[slot]


## The place of `owner`, or -1.
func slot_of(owner: Object) -> int:
	return _slots.get(owner.get_instance_id(), -1)


## The owner of the part in `slot` (null once freed, or for a place not in use).
func owner_at(slot: int) -> Object:
	return instance_from_id(_owners[slot]) if slot < count else null
