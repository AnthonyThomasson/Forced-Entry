class_name BloodPrintConfig
## Footprints (scenes/physics/blood/: BloodField, BloodFootprints): the switch, picking wet blood
## up (the gain, thick blood, the wetness of pools and splats) and stamping prints (the decay, the
## load, the alpha, the jitter, the turn, the slip).
## A `class_name` holder of `static var`s, read as `BloodPrintConfig.<name>`; there is no instance
## and no autoload.

## The footprints' switch: a foot soaks up wet blood where it touches it, then deposits it with the
## load fading, so a trail tapers off. It also needs `BloodConfig.enabled`.
static var footprints_enabled: bool = true
## Seconds a bleed-out pool stays wet enough to be picked up (splatters use
## `BloodSplatConfig.dry_time`).
static var pool_wet_time: float = 240.0
## Wetness (0..1) of a fresh splatter, a thin film next to a pool's deep fill.
static var splat_wetness: float = 0.7
## Load (0..1) a carrier soaks from blood of wetness 1; it keeps the larger of its load and this.
static var pickup_gain: float = 1.0
## Wetness above which the spot is already thick blood: a footprint is not stamped there.
static var thick_blood: float = 0.8
## Footprints: load a foot loses per print (so ~1/decay prints follow a soak), the load below
## which a foot prints nothing, and the print's opacity at load 1 and at the threshold.
static var decay: float = 0.09
static var min_load: float = 0.12
static var alpha_max: float = 0.85
static var alpha_min: float = 0.25
## Random placement offset (px) and turn (radians) of a print, and how far (px) a fast, heavy
## print slips forward along the heading.
static var jitter: float = 0.6
static var turn_jitter: float = 0.12
static var slip: float = 1.2
