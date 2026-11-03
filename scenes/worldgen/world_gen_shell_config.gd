class_name WorldGenShellConfig
## World Generation domain tuning: the ring of shells round a district and how each is built and
## decorated (DistrictLayout, DistrictShells). A `class_name` holder of `static var`s, read as
## `WorldGenShellConfig.<name>`; there is no instance and no autoload.

## The ring of shells past the outer street: how deep each stands from the street (px), the gap
## left between neighbours so each is a building of its own, and its wall's thickness.
static var depth: float = 320.0
static var gap: float = 16.0
static var wall: float = 12.0
## Decor keeps this far (px) in from a shell's wall face.
static var edge: float = 36.0
## A partition's doorway (px): an archway with no door.
static var doorway: float = 60.0
## The shell area (px²) the decor counts are written for; a bigger or smaller shell takes
## proportionally more or fewer pieces.
static var area: float = 240_000.0
## A partition splits a shell at a share of its width between these two.
static var split_min: float = 0.35
static var split_max: float = 0.65
