class_name ObjectMeshNoodleConfig
## Objects domain, the 3D meshes of the noodle bar (`noodle_mesh.gd`; `domain-art/meshes.md`): how
## tall a piece stands. A `class_name` holder of `static var`s, read as
## `ObjectMeshNoodleConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh kit
## converts them to 3D units in one place. A piece's own `art_opts.height` overrides its kind's.

## The bar's top, a stool's seat, a booth's bench seat and its back, the table between the
## benches, and the menu board (where its lower edge hangs and how tall it is).
static var bar_height: float = 40.0
static var stool_height: float = 27.0
static var booth_seat: float = 18.0
static var booth_back: float = 46.0
static var table_height: float = 31.0
static var menu_base: float = 46.0
static var menu_height: float = 34.0
## How thick the menu board is, against the wall at the back of its footprint.
static var menu_depth: float = 4.0
