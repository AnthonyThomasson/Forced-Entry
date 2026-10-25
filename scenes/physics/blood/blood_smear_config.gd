class_name BloodSmearConfig
## A smear's drag (scenes/physics/blood/blood_smear.gd): the switch, the fingers, the speed and the
## segment, the decay and the break into dashes. How a ribbon looks is `BloodSmearLookConfig`.
## A `class_name` holder of `static var`s, read as `BloodSmearConfig.<name>`; there is no instance
## and no autoload.

## The smears' switch: a sliding object soaks up wet blood where it touches it, then deposits it
## with the load fading, so a trail tapers off. It also needs `BloodConfig.enabled`.
static var enabled: bool = true
## Smears: an object drags blood as feathered ribbons, one per "finger" across its footprint. Finger
## spacing (px) and the most fingers; the speed (px/s) below which an object smears nothing; the
## distance (px) between ribbon samples; the load a finger loses per px. A ribbon's width and
## opacity are `BloodSmearLookConfig`'s.
static var finger_spacing: float = 6.0
static var max_fingers: int = 14
static var min_speed: float = 12.0
static var segment_length: float = 3.0
static var decay_per_px: float = 0.007
## Below this load a ribbon starts to break into dry-brush dashes (more often the lower the load),
## and the most samples one ribbon holds before another takes over.
static var break_load: float = 0.3
static var max_ribbon_points: int = 60
