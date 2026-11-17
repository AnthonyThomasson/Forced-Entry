class_name ObjectMeshChairConfig
## Objects domain, the 3D meshes of the office chair and the recliners (`object_meshes.gd`;
## `domain-art/meshes.md`): how tall a piece stands and how its parts are proportioned. A
## `class_name` holder of `static var`s, read as `ObjectMeshChairConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place, so nothing
## here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height` overrides a rule of
## its size.

## An office chair: the seat's top and thickness, the backrest's top and lean (rad), the armrests'
## top and the column's radius.
static var office_seat_height: float = 20.0
static var office_seat_thickness: float = 5.0
static var office_back_height: float = 42.0
static var office_back_lean: float = 0.2
static var office_arm_height: float = 28.0
static var office_column: float = 1.6
## A recliner: the frame's top, the tops of the headrest, backrest, seat and leg rest, the armrests'
## top, the surgeon's lamp arm (height) and the gap between two pads.
static var recliner_frame_height: float = 8.0
static var recliner_head_height: float = 24.0
static var recliner_back_height: float = 30.0
static var recliner_seat_height: float = 18.0
static var recliner_leg_height: float = 14.0
static var recliner_arm_height: float = 22.0
static var recliner_lamp_height: float = 70.0
