class_name NpcRadioTuning extends Node
## An NPC's team radio: whether it sends and hears callouts, how far they carry and how long one
## stays current. One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.radio`), per NPC: its scene authors it (the presets' overrides), a test sets it as an
## indexed path (`tuning:radio:<name>`). Only exports.

## Broadcast this NPC's combat and investigation decisions to allies over the EventBus.
@export var send_callouts: bool = true
## Listen to allies' callouts (their tactic, target and destination).
@export var hear_callouts: bool = true
## How far (px) a callout carries; <= 0 = unlimited.
@export var callout_range: float = 1500.0
## Seconds a heard callout stays current.
@export var callout_ttl: float = 6.0
