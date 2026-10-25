class_name BloodDripConfig
## A wound's drips (scenes/physics/blood/blood_wound.gd): the interval, the budget per damage and
## its cap, the fall, the jitter and the energy, and a drip's splat size.
## A `class_name` holder of `static var`s, read as `BloodDripConfig.<name>`; there is no instance
## and no autoload.

## Seconds between one drip and the next, re-rolled uniformly in [min, max] after every drip (and
## for the first drip after a hit).
static var interval_min: float = 3.0
static var interval_max: float = 10.0
## Drips a hit adds to the wound's budget per point of damage (rounded up, at least 1). The wound
## keeps dripping until the budget is spent, so a harder hit bleeds for longer.
static var drips_per_damage: float = 0.2
## Cap on the drips a wound may owe at once (repeated hits stop adding past it).
static var max_pending_drips: int = 12
## Seconds a drip falls before it lands: it keeps the body's walking velocity meanwhile, so a moving
## body's drops land ahead of where they left it.
static var fall_time: float = 0.18
## Random offset (px) added to where a drip lands.
static var jitter: float = 3.0
## Body speed (px/s) at which a drip lands with full energy (a fully stretched, forward-flung
## splat).
static var full_energy_speed: float = 120.0
## Core blob radius (px) of a drip, in [min, max]; spray splatters are scaled by
## `BloodSprayConfig.hit_splat_size`.
static var size_min: float = 2.5
static var size_max: float = 4.5
