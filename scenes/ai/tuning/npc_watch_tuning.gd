class_name NpcWatchTuning extends Node
## Where an NPC looks (`docs/gaze-and-fire.md`): down its path, at its room's doorways, and at a
## hostile just lost. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.watch`), per NPC: its scene authors it (the presets' overrides), a test sets it as an
## indexed path (`tuning:watch:<name>`). Only exports.

## How far (px) down its path a walking NPC looks: through the doorway it is lining up, not at the
## wall beside it.
@export var look_ahead: float = 150.0
## Seconds a resting NPC looks at one doorway of its room before turning to the next.
@export var door_dwell: float = 2.5
## Seconds a hostile that is no longer in sight still holds the NPC's eyes, while it has a clear
## line to where it was.
@export var lost_gaze: float = 2.0
