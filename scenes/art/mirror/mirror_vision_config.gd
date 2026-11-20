class_name MirrorVisionConfig
## Art domain, the 3D mirror and the player's view (`mirror_sight.gd`, interface 27): how the mirror
## hides what the view does not show. A `class_name` holder of `static var`s, read as
## `MirrorVisionConfig.<name>`.

## How far round its origin a thing that moves (a character, a bullet, a grenade) reaches, px: its
## mesh is hidden when no part of this disc is in the cone the player sees; a vehicle is longer.
static var moving_reach: float = 60.0
static var vehicle_reach: float = 130.0
## The groups of the things the player's view shows only once they have been in its cone: a body
## in one is hidden until the cone has reached it, then stays shown where it is (dimmed, as
## remembered) even after it leaves the cone. A corpse, a dropped item, a parked car; the static
## world (floors, walls, furniture, doors) is remembered from the first sight of the ground.
static var seen_first: Array[StringName] = [
	&"characters", &"vehicles", &"dropped_items", &"live_grenades",
]
