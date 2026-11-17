class_name FurnitureBedRig
extends FurnitureRig
## Objects domain, the rig of a bed: the blanket is a part of its own, and while a
## character's active interaction is this bed's `lie` action the blanket lies flat under them (not
## while it hides under the bed). The one furniture state that needs a look each frame, so the one
## rig with a `mirror_update`: it looks only every `ObjectMeshStateConfig.occupied_every`th frame
## (each bed's first look staggered by its instance id, so the beds do not all look on one frame)
## and writes only when the answer changes. The characters are walked once per frame however many
## beds look (`_lying_beds`). Reads the character duck-typed: `use.is_busy()` and
## `use.active_interaction()` (interface 8).

## The beds a character lies on, by instance id, as of `_lying_frame`: one walk of the characters
## serves every bed looking that frame.
static var _lying: Dictionary = {}
static var _lying_frame := -1

## The blanket's node (its origin on the mattress top, so a flattened scale stays on it).
var blanket: MeshInstance3D
## Whether someone lies on the bed now.
var occupied := false
var _wait := -1


## The mirror calls this each frame the bed shows.
func mirror_update(piece: Node2D) -> void:
	if _wait < 0:
		_wait = first_wait(piece.get_instance_id())
	_wait -= 1
	if _wait > 0:
		return
	_wait = ObjectMeshStateConfig.occupied_every
	var now := _lying_beds(piece.get_tree()).has(piece.get_instance_id())
	if now != occupied:
		set_occupied(now)


## The frames before the bed with instance id `id` first looks: its id modulo the period, so
## beds made together do not all look on one frame.
static func first_wait(id: int) -> int:
	return id % ObjectMeshStateConfig.occupied_every


## Lay the blanket flat (`true`) or raised again.
func set_occupied(on: bool) -> void:
	occupied = on
	if blanket != null:
		blanket.scale.y = ObjectMeshStateConfig.occupied_blanket_scale if on else 1.0


## The instance ids of the beds a character is lying on (their `lie` interaction), worked out
## once per frame.
static func _lying_beds(tree: SceneTree) -> Dictionary:
	var frame := Engine.get_process_frames()
	if frame == _lying_frame:
		return _lying
	_lying_frame = frame
	_lying.clear()
	for node in tree.get_nodes_in_group(&"characters"):
		var use: Variant = node.get("use")
		if use == null or not (use as Object).call(&"is_busy"):
			continue
		var active: Dictionary = (use as Object).call(&"active_interaction")
		var object: Variant = active.get("object")
		if active.get("id") == "lie" and is_instance_valid(object):
			_lying[(object as Object).get_instance_id()] = true
	return _lying
