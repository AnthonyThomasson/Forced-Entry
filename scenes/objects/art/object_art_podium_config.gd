class_name ObjectArtPodiumConfig
## The podium band round a tower's ground floor (podium_painter.gd). The colours are as drawn: the
## painter does not grade its colour (`ObjectArt.AS_GIVEN`). A `class_name` holder of `static var`s,
## read as `ObjectArtPodiumConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`podium_pillar_px` -> `pillar_px`).

## The concrete slab, the step between the pillars along its street edge and a pillar's size (px),
## and the step between the joints cut across it.
static var podium_color: Color = Color(0.47, 0.46, 0.42)
static var podium_pillar_step: int = 48
static var podium_pillar_px: int = 12
static var podium_joint_step: int = 96
