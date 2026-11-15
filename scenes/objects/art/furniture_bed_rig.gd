class_name FurnitureBedRig
extends FurnitureRig
## Objects domain, the rig of a bed (#193 phase 2): the blanket is a part of its own, and while a
## character lies on the bed (an object interaction that snapped it onto the bed's centre) the
## blanket lies flat under them. The one furniture state that needs the body each frame, so it is
## the one rig with a `mirror_update`: it looks only every `ObjectMeshStateConfig.occupied_every`th
## frame and writes only when the answer changes.

## The blanket's node (its origin on the mattress top, so a flattened scale stays on it).
var blanket: MeshInstance3D
## Whether someone lies on the bed now.
var occupied := false
var _wait := 0


## The mirror calls this each frame the bed shows.
func mirror_update(piece: Node2D) -> void:
	_wait -= 1
	if _wait > 0:
		return
	_wait = ObjectMeshStateConfig.occupied_every
	var now := _someone_lies_on(piece)
	if now != occupied:
		set_occupied(now)


## Lay the blanket flat (`true`) or raised again.
func set_occupied(on: bool) -> void:
	occupied = on
	if blanket != null:
		blanket.scale.y = ObjectMeshStateConfig.occupied_blanket_scale if on else 1.0


## Whether a character in an object interaction stands on `piece`'s centre (a `move_to` action
## snaps it there and holds it still).
func _someone_lies_on(piece: Node2D) -> bool:
	for node in piece.get_tree().get_nodes_in_group(&"characters"):
		var character := node as Node2D
		if character == null:
			continue
		var use: Variant = character.get("use")
		if (
			use != null
			and (use as Object).call(&"interaction_label") != ""
			and character.global_position.distance_to(piece.global_position)
				<= ObjectMeshStateConfig.occupied_radius
		):
			return true
	return false
