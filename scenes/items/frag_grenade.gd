class_name FragGrenadeItem extends GrenadeItem
## Items domain: a frag grenade (blast and fragments): everything it does lives in `GrenadeItem`,
## tuned by the frag row of `GrenadeConfig` (its size and its look too); this names the row.

## The kind's id and its `GrenadeConfig` row.
const KIND := &"frag"


func _init() -> void:
	super(KIND)
