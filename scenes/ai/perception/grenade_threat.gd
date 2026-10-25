class_name GrenadeThreat extends RefCounted
## A live grenade as a danger to get clear of (`AgentThrow.escape`, `docs/grenades.md` G16): its
## kind, its danger radius, where it bursts and how long its fuse has left. The perception fills it
## from what it knows of the grenade (seen, heard, called, or its own throw weighed).

## `&"frag"` or `&"stun"`.
var kind: StringName = &""
## Its danger radius, px (the blast's or the flash's, `AgentThrow.radius_of`).
var radius: float = 0.0
## Where it bursts (where it lies, or will come down).
var burst: Vector2 = Vector2.ZERO
## The seconds left before it goes off.
var fuse_left: float = 0.0
