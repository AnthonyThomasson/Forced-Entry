class_name ObjectMeshOverheadConfig
## Objects domain, the 3D meshes of what hangs overhead (`streetlight_mesh.gd`, `awning_mesh.gd`;
## `domain-art/meshes.md`): a street lamp's post, arm and head, and the awning and the hanging sign
## over a tower's front door. A `class_name` holder of `static var`s, read as
## `ObjectMeshOverheadConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh
## kit converts them to 3D units in one place. A wall is 96 tall, a door leaf 84.

## The street lamp: its post's height and radius, the arm's thickness, the cobra head's height and a
## neon sign's height (the board is as wide as the 2D art draws it, and as thick as `sign_depth`).
static var post_height: float = 130.0
static var post_radius: float = 3.5
static var arm_thickness: float = 2.0
static var head_height: float = 9.0
static var sign_height: float = 14.0
static var sign_depth: float = 3.0
## The awning: how high its front edge hangs, how far its cloth rises toward the wall, the board
## along the wall and the valance down its front.
static var awning_front: float = 72.0
static var awning_rise: float = 22.0
static var awning_board: float = 6.0
static var awning_valance: float = 4.0
## The glyph sign: the height of its blade (the width the 2D art draws), how thick it is, and where
## its bracket rod runs.
static var hanging_blade: float = 26.0
static var hanging_depth: float = 4.0
static var hanging_rod: float = 84.0
