class_name GrenadeArt extends ItemArt
## Items domain: how a grenade is drawn, a `GrenadeItem`'s `art` part: its row's look in its weapon
## style (`GrenadeConfig.look`: the painter and colours) at its row's `art_size`, in the hand with
## the lever held down, or in the air and on the floor with the lever gone. It holds the grenade's
## row id and its weapon hand, never the item.

## The kind's id: its `GrenadeConfig` row.
var kind: StringName = &""
## The hand that holds it (its item's `weapon_hand()`).
var hand := 0


func _init(id: StringName, weapon_hand: int) -> void:
	kind = id
	hand = weapon_hand


## How it is drawn: its row's look in its weapon style (`GrenadeConfig.look`: `painter`, colours,
## `finish`).
func look() -> Dictionary:
	return GrenadeConfig.look(kind, style)


## The grenade's 3D mesh in the hand (`GrenadeMesh`), the lever held down.
func held_mesh() -> Mesh:
	var drawn := look()
	return GrenadeMesh.of(kind, drawn, _look_handle(drawn))


## The held art the mesh wears (the lever on it): the painter's unlit render, projected straight
## down.
func held_texture() -> Texture2D:
	var drawn := look()
	return GrenadeMesh.texture(kind, drawn, _look_handle(drawn))


## Where the art lies in the mesh's frame.
func held_rect() -> Rect2:
	return GrenadeMesh.rect(kind)


## The grenade's 3D mesh in the air or on the floor: the lever gone.
func dropped_mesh(_flipped := false) -> Mesh:
	var drawn := look()
	return GrenadeMesh.of(kind, drawn, _look_handle(drawn), false)


## The art of the grenade in the air or on the floor: the lever gone.
func dropped_texture(_flipped := false) -> Texture2D:
	var drawn := look()
	return GrenadeMesh.texture(kind, drawn, _look_handle(drawn), false)
