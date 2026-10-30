extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's state, a data leaf the entry builds once and holds as
## `state`: its phase, the doorway and room, its slot and side, its mode (solo, bang, a pass-by),
## what `Behavior` sets on it each tick, the doorway's geometry and its clocks. The entry and
## `Behavior` read and write it; it decides nothing itself, and holds nothing back.

const StackMember := preload("res://scenes/ai/perception/stack/stack_member.gd")

## approach / stack / pie / cross / corner / clear / rear / done ("" = idle).
var phase := ""
## The doorway's id (agent_entry.gd `opening_id`).
var opening := ""
## The key of the room behind it.
var into := ""
## This NPC's own claim in the doorway's stack (stack_member.gd): its `slot` (its place in the order
## the stack claimed the doorway, 1 = the point), the `side` of the door its slot stands on (1 / -1
## along its wall: the team's, or its own in a split stack, E19), the side it asks for, its claim's
## frame and spot, its move-up, its place in its side's file and its `point`.
var member: StackMember = StackMember.new()
## Nobody else claims the doorway: no barrier, and the pie is sliced from both sides.
var solo := true
## A bang entry (G18): a stun is thrown into the room before anyone crosses. Radioed with every
## claim; the stack is in bang mode only if all of it is.
var bang := false
## A pass-by (E15): the doorway is only secured, from one side of its pie, never crossed or radioed.
var secure := false
## A secure entry got to the end of its pie.
var secured := false
## Set by `Behavior` while it reads an ordered entry's way before its claim (D4): `take_calls` gives
## nothing yet.
var held_back := false
## A threat holds the entrant's eyes this tick (set by `Behavior` from the watch stage): a gaze step
## that cannot settle because the entrant is looking at a hostile counts as settled, so the entry
## carries on instead of waiting at the pie for a gaze the hostile will not let go of.
var gaze_held := false
## A hostile stands in view this tick (set by `Behavior`: seen now, or a moment ago with a clear
## line to where it stood): nobody crosses (E14). The entry holds where it is, outside, and the
## watch stage fires; it goes in once the hostile is gone.
var hostile_in_view := false
## The doorway's geometry (agent_entry.gd `geometry`).
var geo := {}
## Seconds into the phase.
var clock := 0.0
## Seconds since `begin()`.
var time := 0.0
