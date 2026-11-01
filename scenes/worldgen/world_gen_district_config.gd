class_name WorldGenDistrictConfig
## Tuning for a downtown district (DistrictSpawner, DistrictLayout, DistrictStreets): the streets
## and sidewalks between and round the 3 x 3 blocks, and the ring of shells beyond them. A
## `class_name` holder of `static var`s, read as `WorldGenDistrictConfig.<name>`; there is no
## instance and no autoload.

## The asphalt between two blocks and round the grid (px across) and the sidewalk round each block
## (px deep, past the block's edge: a tower's front wall stands on the block's edge, so this is the
## pavement in front of its door).
static var street_width: float = 200.0
static var sidewalk: float = 80.0
## The ring of shells past the outer street: how deep each stands from the street (px), the gap
## left between neighbours so each is a building of its own, and its wall's thickness.
static var shell_depth: float = 320.0
static var shell_gap: float = 16.0
static var shell_wall: float = 12.0
## A street floor is no larger than this on a side (px): a floor is lit as one item, and Godot
## lights an item with at most 15 point lights, so a floor the lamps of a whole block reach would
## drop some.
static var tile_max: float = 360.0
## A junction arm's crossing and stop line take this much of the road (px, from the junction's
## edge); its lane glyph starts `glyph_gap` px past it and is `glyph_length` long. Nothing else
## stands on the crossing, nor on the sidewalk at either end of it.
static var crossing_reach: float = 58.0
static var glyph_gap: float = 16.0
static var glyph_length: float = 124.0
## The street lamps along a block's sidewalks keep this far (px) from its corners.
static var lamp_corner_inset: float = 80.0
## The sidewalk clutter: one slot about every `clutter_every` px of a block's side, jittered by up
## to `clutter_jitter`, its centre `clutter_depth` px in from the curb; it stays
## `clutter_door_clear` px from a doorway.
static var clutter_every: float = 360.0
static var clutter_jitter: float = 70.0
static var clutter_depth: float = 36.0
static var clutter_door_clear: float = 70.0
## Sidewalk clutter keeps this far (px) from the clutter already placed.
static var clutter_gap: float = 6.0
