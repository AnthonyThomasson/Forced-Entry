class_name ObjectArtFabricConfig
## Upholstered and textile pieces (scenes/objects/art/): the sofa (back, arms, cushions, pillows),
## the bed's mattress and the rug (pattern, fringe). A `class_name` holder of `static var`s, read as
## `ObjectArtFabricConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`table_inset` → `inset`).

## Backrest depth and armrest width, as fractions of the sofa's depth / width.
static var sofa_back_depth: float = 0.3
static var sofa_arm_width: float = 0.1
## Target seat-cushion width (art px) and the most cushions a sofa gets.
static var sofa_cushion_width: float = 36.0
static var sofa_max_cushions: int = 4
## Throw pillows in the back corners, hue-shifted from the upholstery by this much (none on a
## run-down sofa).
static var sofa_pillows: bool = false
static var sofa_pillow_hue_shift: float = 0.09
## The bare mattress's ticking and the spacing (art px) of its quilted stripes.
static var bed_mattress_color: Color = Color(0.6, 0.55, 0.42)
static var bed_stripe_px: int = 6
## The pattern by default ("medallion", "stripes" or "plush"), and the fringe's color.
static var rug_pattern: String = "medallion"
static var rug_fringe_color: Color = Color(0.58, 0.5, 0.36)
