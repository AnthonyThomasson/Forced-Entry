class_name ObjectMeshStorageConfig
## Objects domain, the 3D meshes of the cabinet and the shelf (`object_meshes.gd`;
## `domain-art/meshes.md`): how tall a piece stands and how its parts are proportioned. A
## `class_name` holder of `static var`s, read as `ObjectMeshStorageConfig.<name>` (ADR 0003).
## Lengths are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place, so
## nothing here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height` overrides a
## rule of its size.

## A cabinet: how tall it stands (a small footprint, at most `cabinet_low_area` px squared, is a
## nightstand; one with a crown is a wardrobe), its top slab, the gap between two fronts and how
## thick a front is.
static var cabinet_height: float = 56.0
static var cabinet_low_height: float = 40.0
static var cabinet_low_area: float = 1700.0
static var cabinet_tall_height: float = 78.0
static var cabinet_top: float = 3.0
static var cabinet_gap: float = 1.0
static var cabinet_front: float = 1.0
## A shelf: how tall it stands (a short, small one, at most `shelf_short_area`, is a linen shelf;
## a shoe rack is `shelf_shoe_height`), a board's thickness and a side's, and how many px of height
## one level takes.
static var shelf_height: float = 72.0
static var shelf_short_height: float = 50.0
static var shelf_short_area: float = 1600.0
static var shelf_shoe_height: float = 24.0
static var shelf_board: float = 2.0
static var shelf_side: float = 2.0
static var shelf_level: float = 22.0
