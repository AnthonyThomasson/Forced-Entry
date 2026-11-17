class_name BloodSurfaceConfig
## What the floor does to blood (scenes/physics/blood/: BloodSurface, BloodFlow): the grooves
## steering a flow (the resistances, a groove's width) and porous floors soaking it in (the soak
## time, the weight, the slowdown).
## A `class_name` holder of `static var`s, read as `BloodSurfaceConfig.<name>`; there is no instance
## and no autoload.

## Floor texture steering a bleed-out flow (BloodSurface): off = the floor is ignored. Flow-cost
## multipliers per cell: on a groove (grout, plank seam, slab joint), on smooth surface between
## grooves, and on a porous surface (carpet). Low = blood runs there easily.
static var flow: bool = true
static var groove_resist: float = 0.3
static var smooth_resist: float = 2.2
static var porous_resist: float = 3.0
## Blood on a porous surface (carpet, a rug) sinks in: seconds a flooded cell takes to soak. It
## still covers the same floor; it just stops being wet (no prints or smears) and its colour
## mottles.
static var soak_time: float = 20.0
## Fabric drinks the blood, so it does not travel as far: each cell a pool claims on porous surface
## counts as this many cells of the bleed-out budget (`BloodPoolConfig.bleed_out_cells`), so the
## pool covers a smaller area there.
static var porous_cell_weight: float = 3.0
## Blood spreading over porous surface creeps this many times slower (scaled by the share of the
## pool on it).
static var porous_spread_slowdown: float = 4.0
## Half width (px) around a groove line that still counts as on it; about half a flow cell so a cell
## centre reliably lands in a 1-px groove.
static var groove_half_width: float = 2.0
