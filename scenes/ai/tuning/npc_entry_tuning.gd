class_name NpcEntryTuning extends Node
## An NPC's tactical entry (`docs/tactical-entry.md`): whether it enters rooms tactically, and the
## entry's timing and team (waits, dwells, cover and rear security, the approach's cap, an ordered
## stack's wait). One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.entry`), per NPC: its scene authors it (the presets' overrides), a test sets it as an
## indexed path (`tuning:entry:<name>`). Only exports.

## Tactical entry (`docs/tactical-entry.md`): offer doorways into rooms left to search as an ENTER
## tactic, carried out as a team or alone — stack beside the door, slice the pie, cross without
## stopping, take the corners, clear.
@export var enabled: bool = false
## Seconds the point waits at the door, once in its slot, for the rest of the stack before going in
## without them.
@export var ready_timeout: float = 6.0
## Seconds a quiet entry whose stack carries a stun holds at the stack, once the point is in its
## slot, before the point slices the pie: time for a late reason to suspect the room to come up and
## turn it into a bang one (E17). A hostile in view or coming under fire ends it early.
@export var listen_time: float = 3.0
## Seconds a follower leaves after the member ahead of it goes (starts its crossing, on its own side
## of the door; is through, across the door or the human), so the file walks in on its back.
@export var follow_gap: float = 0.0
## Seconds the point looks through the door from each step of the arc.
@export var pie_dwell: float = 0.35
## Seconds an entrant holds its corner, looking across the room, before it clears the rest by sight.
@export var corner_dwell: float = 0.6
## Most seconds the last of a team holds the doorway it came in by, facing back out, once the room
## is clear (it leaves sooner when a teammate holding the room moves on).
@export var rear_security_time: float = 10.0
## Most seconds a member covers a doorway on out of a room the team has cleared, gun through it,
## when no teammate moves on first.
@export var cover_time: float = 8.0
## Seconds a lone entrant looks through each doorway on out of a room it has cleared, once its gaze
## has settled.
@export var watch_dwell: float = 0.8
## Safety cap (s) on reaching the stack, on top of the walk there at walking pace (measured as the
## approach is planned): an entrant that cannot get to its slot in that time gives up its claim.
@export var approach_time: float = 20.0
## Most seconds an ordered stack waits for every living recipient of the order to be in its slot,
## from the first ordered `ready` heard or said (`docs/leadership.md` LD9, D7); an unordered joiner
## is waited for `ready_timeout` as ever.
@export var order_ready_cap: float = 60.0
