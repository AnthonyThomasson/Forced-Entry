class_name GrenadeThrow extends RefCounted
## One throw of a grenade (`ThrownGrenade.spawn`): its kind, where it leaves the hand and where it
## is aimed, who threw it and the weapon style of the item it was thrown from. The grenade item
## fills it as it lets go (`GrenadeItem`); a test may throw one the same way.

## The grenade's kind, a `GrenadeConfig` row: `&"frag"` / `&"stun"`.
var kind: StringName = &""
## Where it leaves the hand, world px.
var from: Vector2 = Vector2.ZERO
## Where it is aimed, world px.
var to: Vector2 = Vector2.ZERO
## Who threw it (its sweep skips the thrower's body; null = nobody).
var thrower: Node = null
## The weapon style it is drawn in, its item's (`Item.style`; left alone = the default style,
## `GrenadeConfig.default_style`).
var style: StringName = GrenadeConfig.default_style
