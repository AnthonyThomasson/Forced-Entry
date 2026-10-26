class_name NpcCoverageTuning extends Node
## How an NPC searches a room by sight: the gaze's turn rate, the room's sample grid, the share to
## see, the budget, when to walk for a view and the inset off the walls. One topic node of the NPC's
## tunables, under its controller's `Tuning` hub (`NpcTuning.coverage`), per NPC: its scene authors
## it (the presets' overrides), a test sets it as an indexed path (`tuning:coverage:<name>`). Only
## exports.

## When searching a room the NPC looks around until it has SEEN (near-)every part of it (view cone +
## line of sight). These tune that coverage. Gaze turn speed (rad/s) as it looks from point to
## point.
@export var look_rate: float = 2.5
## Room sample-grid spacing (px): smaller = finer coverage but more sight rays per tick.
@export var spacing: float = 64.0
## Fraction (0..1) of sampled points that must be seen to call a room covered (1 = all; < 1
## tolerates nooks it can never see into).
@export var target: float = 1.0
## Max seconds spent covering one room before giving up on unseeable spots and re-deciding (safety
## cap).
@export var budget: float = 8.0
## If the nearest unseen point is farther than this (px) or its line is blocked, the NPC walks
## toward it to get a view; otherwise it just turns to look.
@export var approach: float = 300.0
## Inset (px) from a room's walls where coverage sampling starts, so search points sit off the
## walls.
@export var margin: float = 24.0
