class_name ObjectMeshRoomConfig
## Objects domain, the 3D meshes of the bed, the bath and the toilet (`object_meshes.gd`;
## `domain-art/meshes.md`): how tall a piece stands and how its parts are proportioned. A
## `class_name` holder of `static var`s, read as `ObjectMeshRoomConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place, so nothing
## here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height` overrides a rule of
## its size.

## A bed: the frame's top, the mattress's top, a pillow's and the blanket's thickness and the
## headboard's top.
static var bed_frame_height: float = 10.0
static var bed_mattress_height: float = 22.0
static var bed_pillow_height: float = 5.0
static var bed_blanket_height: float = 3.0
static var bed_headboard_height: float = 34.0
## A bath: the tub's rim, its floor and its water, a shower tray's thickness and the screen's top.
static var bath_rim_height: float = 20.0
static var bath_floor_height: float = 4.0
static var bath_water_height: float = 14.0
static var bath_tray_height: float = 3.0
static var bath_screen_height: float = 80.0
static var bath_head_height: float = 78.0
## A toilet: the bowl's rim, the pedestal under it and the cistern's top.
static var toilet_bowl_height: float = 18.0
static var toilet_pedestal_height: float = 8.0
static var toilet_tank_height: float = 30.0
