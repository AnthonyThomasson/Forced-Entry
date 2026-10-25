class_name GrenadeRunner extends RefCounted
## The NPC running from a grenade (`AgentThrow.escape`, `docs/grenades.md` G16): where it starts
## and how fast it walks there. The perception fills it.

## Where the NPC stands (or will stand) when it starts to run, world px.
var from: Vector2 = Vector2.ZERO
## Its pace, px/s (`AgentThrow.run_speed`).
var speed: float = 0.0
