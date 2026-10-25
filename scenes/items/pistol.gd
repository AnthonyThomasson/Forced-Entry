class_name PistolItem extends GunItem
## Items domain: a pistol held in the right hand: short enough to fire point-blank at a wall, held
## at arm's length with the other hand cupping the grip. Everything a gun does lives in `GunItem`,
## tuned by the pistol's `GunConfig` row (its sizes, its hold and its look too); this names the row.

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"pistol"


func _init() -> void:
	super(GUN)
