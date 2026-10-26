extends RefCounted
## AI domain · TEAM — the human's reservation in a stack (`docs/tactical-entry.md` E16), a data leaf
## its `PlayerStack` builds once and holds as `reservation`: the doorway reserved, the human's slot
## and side there, its claim's frame and spot, its radio step and the clocks a held reservation
## keeps. It holds no owner; `clear` gives it up in place.

## The doorway reserved ("" = no reservation).
var opening := ""
## The key of the room the reserved doorway leads into.
var into := ""
## The reserved doorway's geometry (`AgentEntry.geometry`).
var geo := {}
## The human's slot number (1 = the point; 0 = none): the order it claimed in.
var slot := 0
## The side of the door the human stacks on (1 / -1 along its wall).
var side := 0
## The side its slot stands on: `side`, or the other while `side`'s wall is full (E21).
var on := 0
## The physics frame the claim was made on and where the human stood then (E2: same-frame claims
## settle by distance), kept by every repeat of it.
var claim_frame := -1
var claim_pos := Vector2.INF
## The side the team stacks on, as last weighed (a change is weighed again).
var team_side := 0
## The human's latest radio step (claim / ready / going_in / in).
var step := ""
## The physics frame the human's latest crossing began on (-1 for none): restamped each time its
## step goes from a waiting one (claim / ready) to `going_in` or `in`, since a human that brushed
## the funnel steps back out of it, unlike an NPC. A held stack takes it as its go only when it
## began since the order was issued (D14): a crossing already under way then is not restamped.
var crossed_frame := -1
## Seconds until the latest step is radioed again.
var heartbeat := 0.0
## `GameClock.seconds()` the AI ahead of the human was first all through (-1 = not yet).
var ahead_through_at := -1.0
## `GameClock.seconds()` the human was through.
var in_at := -1.0
## Whether the reservation is the human's own claim (it stepped up with no stack forming), not a
## slot in an allied stack.
var own := false


## Give the reservation up: every field but `heartbeat` (read only while one is held) back to none.
func clear() -> void:
	own = false
	opening = ""
	into = ""
	geo = {}
	slot = 0
	side = 0
	on = 0
	claim_frame = -1
	claim_pos = Vector2.INF
	team_side = 0
	step = ""
	crossed_frame = -1
	ahead_through_at = -1.0
	in_at = -1.0
