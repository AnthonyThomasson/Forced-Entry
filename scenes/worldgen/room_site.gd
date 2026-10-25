class_name RoomSite extends RefCounted
## One room as the house being built knows it, which RoomFurnisher and RoomDresser read: its plan
## entry, its walls' thickness, the doorway boxes nothing may stand in, the solid furniture placed
## in it, the node its furniture and clutter go under and the run's seed. HouseSpawner fills it per
## room; RoomFurnisher appends to `solids`. Rects are in the house's space.

## The plan's room, `{ key, type, rect }`.
var room: Dictionary = {}
## The thickness of its walls, px.
var wall_thickness: float = 0.0
## The doorway clearance boxes furniture and dressing stay out of.
var blocked: Array = []
## The footprint (Rect2) of every solid piece of furniture placed so far.
var solids: Array = []
## The node its furniture and clutter are spawned under.
var furniture: Node = null
## The run's seed, which the room's own dressing RNGs are seeded from.
var run_seed: int = 0
