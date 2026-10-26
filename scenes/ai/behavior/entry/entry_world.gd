extends RefCounted
## AI BEHAVIOUR sub-domain — TACTICAL ENTRY's world, a data leaf the entry builds once and holds as
## `world`: what it works with, handed in by `Behavior` (`tuning` before `Entry.setup`, the rest by
## `setup`, `bind` and `apply_config`) and by `Entry.begin` (the NPC's id). Its references are nodes
## and the behaviour's own modules, none of which holds the entry, so no reference cycle forms.

## The NPC's squad (`Squad.alive`: which recipients of an order still live); null without one.
var squad: Node = null
## The Locomotion child (pathing, rooms).
var loco: Node
## The perception sub-domain (doorway geometry, the team on the radio, sight).
var perception: Node
## The room coverage by sight, reused to clear the room once inside.
var coverage: RefCounted
## The combat module: the tactical reload at the stack (`Combat.top_off`).
var combat: RefCounted
## The watch module: where a walking entrant looks (`Watch.travel_point`).
var eyes: RefCounted
## The NPC's body, handed in once by `bind`.
var character: Node
## This NPC's instance id (to know it is the thrower on the radio's terms).
var self_id := 0
## The NPC's tuning, read live: the entry's tunables (`tuning.entry`) and its gaze turn speed
## (`tuning.coverage.look_rate`).
var tuning: NpcTuning
