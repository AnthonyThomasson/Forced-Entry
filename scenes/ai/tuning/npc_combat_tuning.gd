class_name NpcCombatTuning extends Node
## How an NPC fights: its ranges, the ring of fire and cover spots, peek-and-cover, the fire cadence
## and bursts, stepping back off a wall, the reload reflex, and how long gunfire keeps it alert and
## committed. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.combat`), per NPC: its scene authors it (the presets' overrides), a test sets it as
## an indexed path (`tuning:combat:<name>`). Only exports.

## Range (px) of the gun: shots are taken within it, and distances are banded against it for Von.
@export var shoot_range: float = 500.0
## Range (px) within which a punch lands.
@export var punch_range: float = 48.0
## Radius (px) of the ring of candidate fire/cover positions sampled during combat.
@export var ring_radius: float = 80.0
## Number of candidate positions sampled on that ring.
@export var ring_count: int = 12
## Seconds to stay behind cover between shots (the duck half of peek-and-cover).
@export var cover_time: float = 1.2
## Minimum seconds between shots/punches while engaging.
@export var fire_cooldown: float = 0.5
## Rounds an automatic gun fires per trigger pull (at the gun's own fire rate); a single-shot gun
## fires one.
@export var fire_burst: int = 3
## Seconds spent stepping back when the gun's barrel is against a wall or object and cannot fire.
@export var back_off_time: float = 0.45
## Seconds a chosen fire/cover position is committed to before a new one may be picked. Prevents
## per-frame re-selection of the nearest spot (which makes the NPC vibrate).
@export var reposition_interval: float = 0.5
## Reload an empty gun on its own (holding steady, or ducked in cover) when a spare magazine is
## carried, whatever the decision tree chose: the NPC is never left unarmed for lack of a decision.
@export var auto_reload: bool = true
## Radius (px) within which a hit on something else still registers as gunfire near the NPC.
@export var hit_awareness_radius: float = 160.0
## Seconds an incoming/nearby hit keeps the NPC on "under fire" alert (reported to Von, which
## re-decides at once).
@export var under_fire_time: float = 3.0
## Seconds the NPC stays committed to a fight after the last shot it fired or took, before it
## re-asks Von. Stops it dropping out of combat between decisions.
@export var engage_dwell: float = 3.0
