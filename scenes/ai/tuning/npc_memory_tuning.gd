class_name NpcMemoryTuning extends Node
## What an NPC remembers: the event cap, how long a lead, a searched room and a sighting last, and
## whether it starts knowing the house. One topic node of the NPC's tunables, under its controller's
## `Tuning` hub (`NpcTuning.memory`), per NPC: its scene authors it (the presets' overrides), a test
## sets it as an indexed path (`tuning:memory:<name>`). Only exports.

## Hard cap on remembered events (oldest expirable evicted past it); <= 0 = unlimited.
@export var capacity: int = 128
## Seconds a lost hostile's last sighting stays an investigation lead.
@export var lead_ttl: float = 20.0
## Seconds a visited room counts as recently searched.
@export var search_ttl: float = 60.0
## Lifetime (s) of a character sighting — the window the NPC keeps acting on a last-seen position
## after losing sight before the contact becomes a mere investigation lead.
@export var contact_ttl: float = 4.0
## Whether this NPC starts already knowing the house (its rooms + objects). Off = it must see them
## first. People are never pre-known either way — they are known only once seen.
@export var familiar_with_house: bool = true
