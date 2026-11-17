class_name ObjectMeshSeatConfig
## Objects domain, the 3D meshes of the sofa and the chair (`object_meshes.gd`;
## `domain-art/meshes.md`): how tall a piece stands and how its parts are proportioned. A
## `class_name` holder of `static var`s, read as `ObjectMeshSeatConfig.<name>` (ADR 0003). Lengths
## are 2D pixels, the art's units: the mesh kit converts them to 3D units in one place, so nothing
## here is multiplied by `RenderConfig.unit`. A piece's own `art_opts.height` overrides a rule of
## its size.

## A sofa: the frame under the cushions, the seat cushions' top, the armrests' and the backrest's
## tops above the floor, and the seam between two cushions.
static var sofa_frame_height: float = 10.0
static var sofa_seat_height: float = 18.0
static var sofa_arm_height: float = 28.0
static var sofa_back_height: float = 38.0
static var sofa_seam: float = 1.0
## A chair: the seat's top and thickness, the back's top and a leg's width.
static var chair_seat_height: float = 18.0
static var chair_seat_thickness: float = 3.0
static var chair_back_height: float = 36.0
static var chair_leg: float = 3.0
