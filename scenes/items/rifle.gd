class_name RifleItem extends GunItem
## Items domain: an assault rifle: a long automatic shouldered with the butt against the shoulder,
## the trigger hand at the grip and the other hand out on the foregrip, both lying along the barrel.
## Everything a gun does lives in `GunItem`, tuned by the rifle's `GunConfig` row (heavy, fast,
## penetrating rounds; its sizes, its hold and its look too); this names the row. Its barrel is too
## long for a wall: touching one, it comes up off the aim, pointing up with the butt still on the
## shoulder, and cannot fire.

## The kind of magazine it takes (`Magazine.gun`) and its `GunConfig` row.
const GUN := &"rifle"


func _init() -> void:
	super(GUN)
