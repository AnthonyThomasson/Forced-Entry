class_name ThrowAim extends RefCounted
## Where a grenade is to come down and what a spot to throw it from must pass
## (`AgentTactics.throw_spot`, `docs/grenades.md` G17): the spot, how far from it a thrower lets go,
## the room it must not throw from inside, and the lob and walk tests. The snapshot's grenade
## options fill it.

## Where the grenade is to come down, world px.
var spot: Vector2 = Vector2.ZERO
## How far (px) from `spot` a thrower may stand (`AgentThrow.reach_of`).
var reach: float = 0.0
## The room a throw spot must not lie in (the one the hostile holds, which the NPC is outside of);
## an empty rect for none.
var keep_out: Rect2 = Rect2()
## `Callable(from: Vector2) -> bool`: whether the lob onto `spot` from there is clear.
var lob: Callable = Callable()
## `Callable(to: Vector2) -> Dictionary` (`{ path, len, detour }`): the walk there as the NPC would
## walk it and whether the entry guard would stop it on the way; invalid for the plain route, no
## detour.
var route: Callable = Callable()
