class_name MirrorVisionConfig
## Art domain, the 3D mirror and the player's view (`world_mirror.gd`, interface 27): how the mirror
## hides what the view does not show. A `class_name` holder of `static var`s, read as
## `MirrorVisionConfig.<name>`.

## How far round its origin a thing that moves (a character, a bullet, a grenade) reaches, px: its
## mesh is hidden when no part of this disc is in the cone the player sees; a vehicle is longer.
static var moving_reach: float = 60.0
static var vehicle_reach: float = 130.0
