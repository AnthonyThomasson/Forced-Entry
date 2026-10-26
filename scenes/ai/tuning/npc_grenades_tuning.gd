class_name NpcGrenadesTuning extends Node
## How an NPC deals with grenades (`docs/grenades.md`): the evade reflex, how far one is heard, the
## danger margin, the walk to a throw spot and the blind-fire roll. One topic node of the NPC's
## tunables, under its controller's `Tuning` hub (`NpcTuning.grenades`), per NPC: its scene authors
## it (the presets' overrides), a test sets it as an indexed path (`tuning:grenades:<name>`). Only
## exports.

## React to live grenades (`docs/grenades.md` G16): an NPC that sees one, hears it land or is told
## of it, and is in its danger zone, radios it and runs for the nearest safe spot (out of its line,
## behind cover that shields it, or outside the zone), holding it to the burst. Off = it stands and
## takes it.
@export var enabled: bool = true
## How far (px) a grenade coming down is heard (its bounce and rest), seen or not.
@export var hear_grenade: float = 300.0
## How far (px) past a frag's blast radius its danger zone reaches: the NPC runs to be clear of
## that, not only of the blast.
@export var evade_margin: float = 120.0
## Longest walk (px of route) to a throw spot: a grenade out of range or with no clear lob from
## where the NPC stands is thrown from a spot at most this far away that is in range with a clear
## lob (docs/grenades.md G17), else not offered.
@export var throw_spot_walk: float = 250.0
## The chance (0..1) a flash-blinded NPC fires blindly (`docs/grenades.md` G15): rolled once as it
## goes blind (from not blind), on the controller's own seeded RNG. A hit fires one-handed at the
## last-known spot of the hostile it fought; a miss holds its fire until it can see. A further stun
## while it is still blind does not roll again.
@export_range(0.0, 1.0) var blind_fire_chance: float = 0.5
