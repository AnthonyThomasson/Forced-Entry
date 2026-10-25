class_name WorldGenStreetConfig
## Tuning for the street round a house and its street lamps (HouseSpawner): the sidewalk's depth,
## the street's reach, and the lamps' spacing, curb and doorway clearance. A `class_name` holder
## of `static var`s, read as `WorldGenStreetConfig.<name>`; there is no instance and no autoload.

## The street round a house: a sidewalk `sidewalk` px deep hugging its outline, then asphalt
## out to `reach` px from it (past the outdoor ring the nav map walks).
static var sidewalk: float = 44.0
static var reach: float = 300.0
## The street lamps along the front sidewalk (HouseSpawner): one about every `streetlight_every` px
## along it, each up to `streetlight_jitter` px either way off its even spot, its post
## `streetlight_curb` px in from the curb and its arm out over the road; every other one is a neon
## sign. No part of a lamp (its post or its overhang) comes within `streetlight_door_clear` px of a
## front or exit doorway's centre, nor into the strip straight out of one (the doorway's width plus
## `streetlight_door_strip_margin` px each side, `streetlight_door_strip_reach` px out from the
## wall): a lamp that would is dropped, not moved.
static var streetlight_every: float = 260.0
static var streetlight_jitter: float = 50.0
static var streetlight_curb: float = 8.0
static var streetlight_door_clear: float = 140.0
static var streetlight_door_strip_margin: float = 32.0
static var streetlight_door_strip_reach: float = 400.0
