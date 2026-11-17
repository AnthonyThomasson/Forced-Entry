class_name ObjectMeshConfig
## Objects domain, the 3D meshes of furniture (`object_meshes.gd`; `domain-art/meshes.md`): how tall
## a piece stands and how its parts are proportioned. A `class_name` holder of `static var`s, read
## as `ObjectMeshConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit
## converts them to 3D units in one place, so nothing here is multiplied by `RenderConfig.unit`.

## A table: the height of its top above the floor (a standing character is 74), how thick the top
## slab is, how wide each leg is and how far a leg stands in from the corner of the footprint.
static var table_height: float = 30.0
## A small table (a footprint of at most `table_low_area` px squared: a side table) stands this high
## instead; a piece's `art_opts.height` overrides both.
static var table_low_height: float = 22.0
static var table_low_area: float = 1600.0
static var table_top_thickness: float = 4.0
static var table_leg: float = 5.0
static var table_leg_inset: float = 3.0
