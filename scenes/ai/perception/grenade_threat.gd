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
## How high (px) its centre is over the floor there: a grenade on the floor's, one at rest on a
## desk or a shelf its top's more (`Explosion.BURST_CENTRE` plus `ThrownGrenade.altitude()`).
var burst_height: float = Explosion.BURST_CENTRE
## The seconds left before it goes off.
var fuse_left: float = 0.0


## The burst point in the twin space: `burst` lifted to `burst_height`.
func point() -> Vector3:
	return PlanSpace.lift(burst, burst_height)
