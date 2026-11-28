class_name MirrorSight
extends RefCounted
## Art domain, the player's view as the 3D picture's meshes read it (`MirrorVisionConfig`,
## `docs/player-vision.md` V5, V6 and V12): whether a drawn thing is hidden because the cone does
## not reach it. One per drawer of meshes (the mirror, the group follower), as it keeps which things
## the view has seen where they are.

## The things (instance id -> true) the view has seen where they are: kept while a thing is drawn
## again (a dent, an outfit), cleared the frames it moves outside the cone.
var _seen: Dictionary = {}


## Whether a thing the player's view does not show hides `body`'s mesh now: it moves and wholly lies
## outside the cone (a character the viewer's eye sees no point of included), or is one the view
## shows only once it has been in the cone (`MirrorVisionConfig.seen_first`) and has not been yet.
## `cache` is a dictionary of the drawer's own for this body (its row): it holds what is worked out
## once. With no view (`SeenArea` holds no area) nothing is hidden.
func hides(body: Node2D, cache: Dictionary) -> bool:
	if unseen(body):
		_seen.erase(body.get_instance_id())  # a thing that moves out of view is to be seen again
		return true
	return _not_yet_seen(cache, body)


## Forget that the thing of instance id `id` was seen (it was freed).
func forget_id(id: int) -> void:
	_seen.erase(id)


## Forget that `body` was seen (it left the tree, or is drawn from scratch).
func forget(body: Node) -> void:
	_seen.erase(body.get_instance_id())


## Whether `body` is a thing the player's view never remembers (its 2D node is on
## `ViewLayers.MOVING`: a living character, a car under way, a thrown grenade) while a view is on
## (`ToonMask`): the shaders draw such a thing only where the live cone shows it.
static func moves(body: Variant) -> bool:
	return (
		ToonMask.mask_active()
		and is_instance_valid(body)
		and ((body as CanvasItem).visibility_layer & ViewLayers.MOVING) != 0
	)


## Whether `body` moves and wholly lies outside the cone the player sees now, or is a character in
## it that the viewer's eye sees no point of (ducked behind a sofa: `SeenArea.hides`): its reach is
## a disc of `MirrorVisionConfig.moving_reach` px, a vehicle's `vehicle_reach`.
func unseen(body: Node2D) -> bool:
	if body.visibility_layer & ViewLayers.MOVING == 0:
		return false
	if not SeenArea.reaches(body.global_position, _reach(body)):
		return true
	return SeenArea.hides(body)


## Whether `body` is shown only once seen and has not been (it is marked seen the frame the cone
## first reaches it).
func _not_yet_seen(cache: Dictionary, body: Node2D) -> bool:
	var id := body.get_instance_id()
	if _seen.has(id) or not SeenArea.active():
		return false
	if not cache.has("first"):
		cache["first"] = MirrorVisionConfig.seen_first.any(
			func(group: StringName) -> bool: return body.is_in_group(group)
		)
	if not cache["first"]:
		return false
	if SeenArea.reaches(body.global_position, _reach(body)):
		_seen[id] = true
		return false
	return true


## How far round its origin (px) a thing that moves reaches: a vehicle's is longer.
func _reach(body: Node) -> float:
	return (
		MirrorVisionConfig.vehicle_reach
		if body.is_in_group(&"vehicles")
		else MirrorVisionConfig.moving_reach
	)
