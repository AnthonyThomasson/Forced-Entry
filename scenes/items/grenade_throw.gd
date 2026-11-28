class_name GrenadeThrow extends RefCounted
## One throw of a grenade (`ThrownGrenade.spawn`): its kind, where it leaves the hand and where it
## is aimed, who threw it and the weapon style of the item it was thrown from. The grenade item
## fills it as it lets go (`GrenadeItem`); a test may throw one the same way.

## The grenade's kind, a `GrenadeConfig` row: `&"frag"` / `&"stun"`.
var kind: StringName = &""
## Where it leaves the hand, world px, and how high (px, the posture's `BodyHeights.release`).
var from: Vector2 = Vector2.ZERO
var release: float = BodyHeights.release(BodyHeights.STAND)
## Where it is aimed, world px.
var to: Vector2 = Vector2.ZERO
## Who threw it (its sweep skips the thrower's body; null = nobody).
var thrower: Node = null
## The weapon style it is drawn in, its item's (`ItemArt.style`; left alone = the default style,
## `GrenadeConfig.default_style`).
var style: StringName = GrenadeConfig.default_style
## The apex (px, the centre's height) the thrower chose for the arc, or -1 to throw the lowest arc
## that clears what is in the way (`GrenadeArc`).
var apex: float = -1.0
