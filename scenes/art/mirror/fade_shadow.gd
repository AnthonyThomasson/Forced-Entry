class_name FadeShadow
extends RefCounted
## Art domain, the shadows of one fade unit's instances (`fade_unit.gd`): a unit more than half
## faded casts none (a stippled shadow darkens the character behind it) and gets each instance's own
## setting back when it returns.

## What each instance's `cast_shadow` was when the unit was made, and whether they cast none now.
var casts: Array[GeometryInstance3D.ShadowCastingSetting] = []
var off := false


## Remember the shadow setting each of `parts` has now.
func remember(parts: Array[GeometryInstance3D]) -> void:
	for part in parts:
		casts.append(part.cast_shadow)


## Give `parts` their own shadow setting back (`casting`) or none; whether it wrote (only when that
## changed).
func apply(parts: Array[GeometryInstance3D], casting: bool) -> bool:
	if casting != off:
		return false
	off = not casting
	for i in parts.size():
		if is_instance_valid(parts[i]):
			parts[i].cast_shadow = (
				casts[i] if casting else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			MeshNodes.changed(parts[i])
	return true
