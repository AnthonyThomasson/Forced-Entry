class_name NpcPaceTuning extends Node
## How an NPC moves: the straight-line arrival, running and its thresholds, and the crouch while
## fighting. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.pace`), per NPC: its scene authors it (the presets' overrides), a test sets it as an
## indexed path (`tuning:pace:<name>`). Only exports.

## How close (px) counts as "arrived" when steering straight-line (no nav agent).
@export var arrive_dist: float = 10.0
## Running: may the NPC sprint (spending stamina) on the way to a destination when its decision-tree
## node asks for it (`run`) or it is under fire.
@export var run_enabled: bool = true
## Only run when the destination is farther than this (px), so short hops don't burn stamina.
@export var run_min_distance: float = 150.0
## Stamina fraction (0..1) needed to start a run; once running it goes on until the Character runs
## dry.
@export var run_start_fraction: float = 0.5
## Crouch while fighting in place (kneel behind cover, keep low when pinned), standing to run and
## move. Off = the NPC always stands.
@export var posture_enabled: bool = true
## Seconds a crouch is held before the NPC stands again, so a peek-and-duck does not flicker.
@export var posture_dwell: float = 0.7
