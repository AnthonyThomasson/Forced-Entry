class_name SmgItem extends GunItem
## Items domain: a submachine gun: a compact automatic held in both hands with its butt on the right
## shoulder, a longer reach than a pistol but nowhere near a rifle. Everything a gun does lives in
## `GunItem`, tuned by the SMG's `GunConfig` row (fast, light rounds, a wide spread; its sizes, its
## hold and its look too); this names the row. Its barrel is too long for a wall: touching one, it
## points up and cannot fire.

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"smg"


func _init() -> void:
	super(GUN)
