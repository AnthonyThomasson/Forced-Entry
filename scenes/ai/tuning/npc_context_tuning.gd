class_name NpcContextTuning extends Node
## How what an NPC knows is worded for Von: the recency and route bands, aim and stillness, the lead
## distance, the wound thresholds, the ammo that reads as low and how many contacts the state
## describes. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.context`), per NPC: its scene authors it (the presets' overrides), a test sets it as
## an indexed path (`tuning:context:<name>`). Only exports.

## Ages (s) up to which something counts as "just now" (x) and "recently" (y); older is "a while
## ago".
@export var recency_bands: Vector2 = Vector2(2.0, 8.0)
## Route lengths (px) up to which a route is "short" (x) and "medium" (y); longer is "long".
@export var route_buckets: Vector2 = Vector2(400.0, 900.0)
## Half-angle (degrees) within which a seen character's facing counts as aiming at someone.
@export var aim_cone: float = 20.0
## Speed (px/s) under which a seen character counts as standing still.
@export var still_speed: float = 20.0
## Smoothing (0–1) of a seen character's tracked velocity; higher follows changes faster.
@export var track_smoothing: float = 0.3
## Most seconds a lost hostile's last-seen velocity is projected forward ("where they were
## heading").
@export var extrapolate_cap: float = 3.0
## Distance (px) toward unseen gunfire the "where the shots came from" lead points.
@export var investigate_distance: float = 300.0
## Accumulated damage (see Character.damage_taken) at or above which a character reads as "hurt".
@export var hurt_threshold: float = 15.0
## Accumulated damage at or above which a character reads as "badly wounded".
@export var critical_threshold: float = 35.0
## A gun holding this fraction of its magazine or less reads as "nearly empty" (and offers a
## reload).
@export var low_ammo_fraction: float = 0.34
## Most contacts described in the decision state (hostiles first, then nearest).
@export var max_contacts_in_state: int = 4
