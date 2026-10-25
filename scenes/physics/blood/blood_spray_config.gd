class_name BloodSprayConfig
## A hit's spray (scenes/physics/blood/blood_wound.gd): the splatters per damage and their cap,
## the spray's reach, spread and energy, and a spray splatter's size.
## A `class_name` holder of `static var`s, read as `BloodSprayConfig.<name>`; there is no instance
## and no autoload.

## Damage per spray splatter a hit throws (rounded up, at least 1), and the most one hit throws.
static var hit_splat_damage: float = 8.0
static var hit_splat_max: int = 5
## How far (px) from the wound a spray splatter lands, in [min, max], along the wound's exit side
## (the surface normal) with a random spread of `spread` radians either side.
static var reach_min: float = 10.0
static var reach_max: float = 48.0
static var spread: float = 0.6
## Energy (0..1) of a spray splatter: how stretched along its flight and how far its satellites
## scatter.
static var energy: float = 0.8
## A spray splatter's core radius, as a share of a drip's (`BloodDripConfig.size_min`..`size_max`).
static var hit_splat_size: float = 0.7
