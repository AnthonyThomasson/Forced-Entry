class_name NpcTacticsTuning extends Node
## An NPC's combat geometry: cover, the flank sides, route clearance, a hostile's watch cone and the
## firing spots sampled. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.tactics`), per NPC: its scene authors it (the presets' overrides), a test sets it as
## an indexed path (`tuning:tactics:<name>`). Only exports.

## Surface coverage (0–100) at or above which a blocking object counts as usable cover.
@export var cover_min: float = 40.0
## Distance (px) from a target at which a flanking spot is sought.
@export var flank_distance: float = 220.0
## Angular spread (degrees) sampled around each flank side's bearing.
@export var flank_arc: float = 60.0
## An ally within this distance (px) of a target holds the side it stands on, so this NPC is told
## that side is taken.
@export var flank_ally_radius: float = 500.0
## A route that comes within this distance (px) of a known hostile, nearer than the NPC already is,
## passes them: such a flank side is never offered, nor is such a firing spot.
@export var route_clearance: float = 120.0
## Full width (degrees) of the cone around a hostile's front in which it counts as looking. A firing
## spot in the open inside that cone, with a clear line from the hostile, is never offered.
@export var watch_arc: float = 90.0
## Distances (px) from a target at which firing spots around it are sampled (besides those a step or
## two from the NPC).
@export var fire_spot_distances: Array[float] = [200.0, 350.0]
