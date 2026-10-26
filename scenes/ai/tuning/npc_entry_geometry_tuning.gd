class_name NpcEntryGeometryTuning extends Node
## The doorway geometry of an NPC's tactical entry, which its perception lays out: the stack's
## slots, the pie's arc, the corners and the short room. One topic node of the NPC's tunables, under
## its controller's `Tuning` hub (`NpcTuning.entry_geometry`), per NPC: its scene authors it (the
## presets' overrides), a test sets it as an indexed path (`tuning:entry_geometry:<name>`). Only
## exports.

## Distance (px) between neighbouring stack slots along the wall: clear of a neighbour's footprint
## (the 34 px hole a body at rest cuts in the steering map, plus room to spare), so a slot never
## lies in the hole of the member beside it.
@export var stack_spacing: float = 44.0
## Distance (px) of a stack slot off the wall's centreline.
@export var wall_standoff: float = 28.0
## Distance (px) from the threshold of the arc the point slices the pie from.
@export var pie_radius: float = 100.0
## Angle steps on that arc.
@export var pie_steps: int = 5
## Inset (px) of a corner point from the room's walls: where an entrant stops in a corner.
@export var corner_inset: float = 40.0
## A room with a side under this (px) is too small for the team (about three bodies): two go in, the
## rest hold the stack side.
@export var short_room: float = 150.0
