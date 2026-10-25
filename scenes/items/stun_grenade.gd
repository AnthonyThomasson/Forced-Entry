class_name StunGrenadeItem extends GrenadeItem
## Items domain: a stun grenade (flash and bang): everything it does lives in `GrenadeItem`, tuned
## by the stun row of `GrenadeConfig` (its size and its look too); this names the row.

## The kind's id and its `GrenadeConfig` row.
const KIND := &"stun"


func _init() -> void:
	super(KIND)
