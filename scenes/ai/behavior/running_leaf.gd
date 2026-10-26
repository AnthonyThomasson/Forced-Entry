extends RefCounted
## AI BEHAVIOUR sub-domain — the running leaf, a data leaf the behaviour builds once and holds as
## `task`: the primitive it runs and that leaf's params, path and labels, when it was adopted, where
## it goes and whether it has got there, its commitment and tactic clocks, and whether it is
## resolved (the controller's cue to re-decide, `take_resolved`). `Behavior` and its stages read and
## write it; it decides nothing itself.

## The running primitive.
var primitive: StringName = &"hold"
## Its params (from the leaf).
var params := {}
## The decision path ids (e.g. ["combat", "t_12", "flank", "side_left"]).
var path: Array = []
## The decision path as labels (e.g. ["COMBAT", "Intruder", "FLANK", "their left side (kitchen)"]).
var labels: Array = []
## When the running leaf was adopted (game msec, `GameClock.msec()`).
var leaf_ms := 0
## The leaf's destination, snapped onto the navmesh.
var point := Vector2.ZERO
## A move that completes on ENTERING this room ("" = on reaching `point`); ignored while looking
## around.
var arrive_room := ""
## Whether the destination has been reached.
var arrived := false
## A search/explore move that covers the room by sight on arrival (vs resolving at once).
var look_around := false
## Seconds left on the current move/approach commitment (safety cap).
var commit_timer := 0.0
## Seconds left before a fight re-asks which tactic to use.
var tactic_timer := 0.0
## A task just finished (arrived / interaction ended / target lost) → re-decide.
var resolved := false
## Why the task is resolved, read before `take_resolved()`: "way blocked" when a body seals the only
## way of its walk and stays, "after the bang" when the bang's thrower has thrown with a decision
## held off ("" = it finished).
var resolve_reason := ""
## A decision came back while the bang's thrower was committed to its throw: it is taken again once
## the stun is away.
var held := false


## Whether a committed task just finished (arrived / interaction ended / target lost while
## deciding), or its walk is blocked (`resolve_reason`). Clears the flag and its reason; the
## controller forces a re-decision when it returns true.
func take_resolved() -> bool:
	var r := resolved
	resolved = false
	resolve_reason = ""
	return r
