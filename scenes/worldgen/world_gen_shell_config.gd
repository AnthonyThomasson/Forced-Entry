class_name WorldGenShellConfig
## World Generation domain tuning: how a district shell is built and decorated (DistrictShells). A
## `class_name` holder of `static var`s, read as `WorldGenShellConfig.<name>`; there is no instance
## and no autoload.

## Decor keeps this far (px) in from a shell's wall face.
static var shell_edge: float = 36.0
## A partition's doorway (px): an archway with no door.
static var shell_doorway: float = 60.0
## The shell area (px²) the decor counts are written for; a bigger or smaller shell takes
## proportionally more or fewer pieces.
static var shell_area: float = 240_000.0
## A partition splits a shell at a share of its width between these two.
static var shell_split_min: float = 0.35
static var shell_split_max: float = 0.65
