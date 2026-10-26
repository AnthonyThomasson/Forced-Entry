extends RefCounted
## AI DECISION sub-domain: the decision walk in flight, a data leaf the planner builds once and
## holds as `_walk`. The snapshot it decides over, the level being decided, what is bound and
## whether it is inside a confined subtree, the path chosen so far, the level's options and its
## per-level records. `begin` resets it for each walk; the planner reads and writes it as it steps.

## The perception snapshot the walk in flight decides over.
var snap := {}
## The node whose level is being decided.
var node: StringName = &""
## Bound values so far (e.g. { "target": "Intruder", "target_id": 123 }).
var binding := {}
## Whether the walk is inside a confined subtree for a territorial NPC or one keeping to a room.
var confine := false
## The path chosen so far: [{ id, label }].
var steps: Array = []
## The in-flight level's options: id → { kind, desc, label, … }.
var offered := {}
## Whether the in-flight level is a bind step.
var bind_level := false
## Per-level records of the walk in flight.
var levels: Array = []
## When the in-flight question was sent.
var asked_ms := 0
