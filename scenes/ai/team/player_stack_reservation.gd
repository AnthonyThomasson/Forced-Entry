extends RefCounted
## AI domain · TEAM — the human's reservation in a stack (`docs/tactical-entry.md` E16), a data leaf
## its `PlayerStack` builds once and holds as `reservation`: the doorway reserved, the human's own
## claim there (its stack `member`: its slot and side, the side it asks for, the claim's frame and
## spot, its radio step, the frame its latest crossing began on and whether it is the human's own
## claim) and the clocks a held reservation keeps. It holds no owner; `clear` gives it up in place.

const StackMember := preload("res://scenes/ai/perception/stack/stack_member.gd")

## The doorway reserved ("" = no reservation).
var opening := ""
## The key of the room the reserved doorway leads into.
var into := ""
## The reserved doorway's geometry (`AgentEntry.geometry`).
var geo := {}
## The human's own claim in the stack (stack_member.gd): `slot` (1 = the point; 0 = none: the order
## it claimed in), `side` (where its slot stands: the side it asks for, `want`, or the other while
## that side's wall is full, E21), `claim_frame` / `claim_pos` (E2: same-frame claims settle by
## distance, kept by every repeat of it), `step` (its latest radio step: claim / ready / going_in /
## in), `crossed_frame` (restamped each time its step goes from a waiting one to `going_in` or
## `in`, since a human that brushed the funnel steps back out of it, unlike an NPC: a held stack
## takes it as its go only when it began since the order was issued, D14) and its terms (`human`,
## `leader`, `own`: its own claim, it stepped up with no stack forming, not a slot in an allied
## stack).
var member: StackMember = StackMember.new()
## Seconds until the latest step is radioed again.
var heartbeat := 0.0
## `GameClock.seconds()` the AI ahead of the human was first all through (-1 = not yet).
var ahead_through_at := -1.0
## `GameClock.seconds()` the human was through.
var in_at := -1.0


## Whether the reservation is the human's own claim (LD24), not a slot in an allied stack.
func own() -> bool:
	return bool(member.terms.get("own", false))


## Give the reservation up: every field but `heartbeat` (read only while one is held) back to none.
func clear() -> void:
	opening = ""
	into = ""
	geo = {}
	member.clear()
	ahead_through_at = -1.0
	in_at = -1.0
