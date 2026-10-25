class_name BloodSmearLookConfig
## How a smear ribbon looks (scenes/physics/blood/: BloodSmear, BloodDecals): its width, its alpha
## and how fast it rises, its wobble and feather, and how it eases into and is absorbed by blood
## already on the floor.
## A `class_name` holder of `static var`s, read as `BloodSmearLookConfig.<name>`; there is no
## instance and no autoload.

## Ribbon width as a multiple of the finger spacing (more than 1 so neighbours merge into one
## smudge), and the opacity at load 1.
static var width: float = 1.7
static var alpha_max: float = 0.95
## How far a ribbon wanders sideways (in finger spacings) and how fast (cycles per px), so streaks
## drift, converge and cross instead of running dead straight.
static var wobble: float = 0.6
static var wobble_freq: float = 0.03
## Opacity at a ribbon's edges as a fraction of its centre (0 = fully soft, 1 = hard edge).
static var feather: float = 0.25
## Blending into blood already on the floor: a new ribbon eases in over this many px, and is
## see-through where the floor is already wet — fully so above `absorb_hi` wetness, not at all
## below `absorb_lo` — so a smear grows out of its puddle with no edge.
static var fade_in: float = 12.0
static var absorb_lo: float = 0.1
static var absorb_hi: float = 0.6
## The most a ribbon's opacity may rise per sample (it may fall at once), so a streak swells out of
## a puddle's crisp edge instead of switching on there.
static var alpha_rise: float = 0.12
