class_name WearPlan extends RefCounted
## Where a room's wear gathers and what it lies on, as `WearFactory.spawn` takes it: World-Gen's
## placement of the clusters, the room's floor and how thick its walls are. Objects decides each
## cluster's marks from it.

## The room's floor (a catalogue floor definition: the marks follow its `art_opts.pattern` and
## colour).
var floor_definition: Dictionary = {}
## The room's walls' thickness, px.
var wall_thickness: float = 0.0
## The clusters, `{ pos, wall, seed }` each: its centre; the free stretch of wall it is by as
## `[a, b]`, its centre line between two points, or `[]`; the seed of its marks; all in the wear
## node's parent's space.
var clusters: Array = []
