class_name ObjectMeshStreetConfig
## Objects domain, the 3D meshes of the sidewalk's props and the tower's podium
## (`street_prop_mesh.gd`, `podium_mesh.gd`; `domain-art/meshes.md`): how tall a piece stands. A
## `class_name` holder of `static var`s, read as `ObjectMeshStreetConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place. A piece's
## own `art_opts.height` overrides its kind's.

## The vending machine, the bench's seat, the bin and how far its lid rises over its body.
static var vending_height: float = 78.0
static var bench_seat: float = 19.0
static var bin_height: float = 38.0
static var bin_lid: float = 2.0
## How high a drain grate's frame and bars stand and how high a scrap of litter lies.
static var grate_height: float = 0.6
static var litter_height: float = 1.2
## The podium: its slab, and where the tops of the pillars along its street edge stand.
static var podium_height: float = 10.0
static var pillar_height: float = 64.0
