class_name NpcHostilityTuning extends Node
## Whom an NPC takes for hostile: on sight, on trespass, on attack, and how long a verdict lasts.
## One topic node of the NPC's tunables, under its controller's `Tuning` hub
## (`NpcTuning.hostility`), per NPC: its scene authors it (the presets' overrides), a test sets it
## as an indexed path (`tuning:hostility:<name>`). Only exports.

## Every non-allied character seen is hostile (e.g. an invader).
@export var on_sight: bool = false
## A non-allied character seen inside the house is hostile (e.g. a defender).
@export var on_trespass: bool = false
## A non-allied character that attacks this NPC — hits it, or shoots close to it — is hostile.
@export var on_attack: bool = true
## Lifetime (s) of a hostility verdict; <= 0 = permanent (a grudge never fades).
@export var ttl: float = 0.0
