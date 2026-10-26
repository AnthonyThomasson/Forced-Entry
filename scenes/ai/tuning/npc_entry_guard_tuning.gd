class_name NpcEntryGuardTuning extends Node
## An NPC's entry guard (`docs/tactical-entry.md` E9, E15, E18): whether any walk into a room not
## cleared goes in by entry, its reach and re-arm, the doorways secured in passing, and the doorway
## views a walk keeps out of. One topic node of the NPC's tunables, under its controller's `Tuning`
## hub (`NpcTuning.entry_guard`), per NPC: its scene authors it (the presets' overrides), a test
## sets it as an indexed path (`tuning:entry_guard:<name>`). Only exports.

## The entry guard (E9): any walk that would cross into a room that is not cleared goes in by
## tactical entry first, whatever order it came from. Needs `tuning.entry.enabled`. A retreat and an
## NPC under fire are exempt.
@export var enabled: bool = true
## Distance (px of walking) from such a doorway at which the guard starts the entry.
@export var reach: float = 300.0
## Seconds a doorway whose entry was given up (a fight, a failed start) is left alone before the
## guard may try it again.
@export var rearm: float = 6.0
## Seconds a doorway the NPC secured as it passed (E15: a doorway on its walk in a corridor, not
## crossed) is left alone before the guard may secure it again.
@export var secure_time: float = 30.0
## Seconds a cleared room counts as safe to walk past (its doorways' views are then left alone);
## after it they are avoided or secured again.
@export var pass_clear_time: float = 60.0
## How far (px) out of a doorway its view reaches, along the rays from the room's far corners
## through the opposite jambs (stopped at walls): a walk keeps out of the view of every doorway into
## a room not clear for passing (E18).
@export var door_view_depth: float = 450.0
## A walk round those views is taken when it is no longer than this many times the plain route...
@export var door_avoid_ratio: float = 2.0
## ... plus this many px. Longer, or none: the walk goes the plain way, and the guard secures each
## doorway view it crosses (E15).
@export var door_avoid_slack: float = 300.0
