class_name ObjectMeshShopConfig
## Objects domain, the 3D meshes of the tower's shop and stockroom (`shop_mesh.gd`,
## `stock_mesh.gd`; `domain-art/meshes.md`): how tall a piece stands. A `class_name` holder of
## `static var`s, read as `ObjectMeshShopConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's
## units: the mesh kit converts them to 3D units in one place. A piece's own `art_opts.height`
## overrides its kind's.

## The shop: the counter and the till on it, the shelf aisle and how many tiers a run has, the
## drinks fridge and the snack machine.
static var counter_height: float = 36.0
static var till_height: float = 12.0
static var aisle_height: float = 58.0
static var aisle_tiers: int = 3
static var fridge_height: float = 70.0
static var snack_height: float = 66.0
## The stockroom: one crate of a stack, a pallet's slats and a wrapped box on it, the safe.
static var crate_height: float = 18.0
static var pallet_height: float = 5.0
static var pallet_box_height: float = 26.0
static var safe_height: float = 40.0
