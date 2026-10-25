class_name BloodSplatConfig
## A splatter's shape (scenes/physics/blood/blood_splat.gd): its spikes, satellites, stretch and
## wobble, its drying and highlight, and the most splatters one body keeps.
## A `class_name` holder of `static var`s, read as `BloodSplatConfig.<name>`; there is no instance
## and no autoload.

## Crown spikes radiating from the core, and the satellite droplets scattered around it, in [min,
## max].
static var spikes_min: int = 4
static var spikes_max: int = 10
static var satellites_min: int = 4
static var satellites_max: int = 12
## How far a splatter stretches along its direction at full energy (core length = radius * (1 +
## this)).
static var stretch: float = 0.9
## How lumpy the core outline is (1 +- this per vertex). 0 = a clean disc.
static var wobble: float = 0.22
## Spike length, in core radii, in [min, max]; and how far satellites land, in core radii.
static var spike_length_min: float = 0.4
static var spike_length_max: float = 1.6
static var satellite_reach_min: float = 1.4
static var satellite_reach_max: float = 3.4
## Seconds a splatter takes to dry from `color` to `dried_color`.
static var dry_time: float = 90.0
## Wet highlight painted on the core (a lighter fleck); alpha 0 hides it.
static var highlight: Color = Color(0.75, 0.12, 0.12, 0.45)
## Cap on the splatters one body keeps in the world; the oldest are freed past it.
static var max_splats_per_body: int = 60
