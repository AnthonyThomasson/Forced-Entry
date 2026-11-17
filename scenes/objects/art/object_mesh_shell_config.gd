class_name ObjectMeshShellConfig
## Objects domain, the 3D meshes of a shell's loose things and a house's walk-over clutter
## (`shell_decor_mesh.gd`, `decor_mesh.gd`; `domain-art/meshes.md`): how high each lies. A
## `class_name` holder of `static var`s, read as `ObjectMeshShellConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place.

## Rebar: how thick a rod is; rubble: the lowest and the highest a chunk stands; scaffold: the
## tubes' height and how thick a board is; cement: a bag's height.
static var rod: float = 2.5
static var rubble_low: float = 2.0
static var rubble_high: float = 7.0
static var tube: float = 8.0
static var board: float = 2.0
static var bag: float = 7.0
## A wall stain: where the streaks start down the wall, and how far they stand off it.
static var stain_top: float = 88.0
static var stain_lift: float = 0.4
## Clutter: a cable's thickness, a flattened box and the blanket on it, standing water, a neon tube.
static var cable: float = 1.4
static var cardboard: float = 1.4
static var blanket: float = 3.0
static var puddle: float = 0.25
static var neon_tube: float = 3.0
