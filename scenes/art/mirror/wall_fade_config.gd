class_name WallFadeConfig
## Art domain, the wall fade of the 3D render (`wall_fade.gd`, #193 rule 9, interface 27): which
## walls and tall pieces thin out so the character is never hidden, and how. A `class_name` holder
## of `static var`s, read as `WallFadeConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's
## units; the fade converts them to 3D units once (`RenderConfig.unit`).

## How far from a focus (the player, or each character when spectating) along the line to the
## camera a piece may stand and still fade. A piece also fades only while it is taller than that
## line is high where it meets it, so a standing wall's reach is its height over the camera's
## tangent (96 px: about 136 px at the isometric pitch), whichever of the two is shorter.
static var radius: float = 160.0
## Seconds a piece takes to go from whole to faded, and back: it never pops.
static var fade_time: float = 0.25
## How much of a faded piece is drawn (`MeshNodes.fade`'s amount: a dither of the picture's
## pixels): 1 whole, 0 gone. Low enough to see the character through, not gone, so a wall still
## reads as a wall.
static var faded_amount: float = 0.2
## A piece fades only if it stands at least this tall (a standing character is 74, a wall 96):
## a low table or crate never hides anyone, so it is never looked at.
static var tall_height: float = 48.0
## The character's half width: a piece fades when the line from a focus to the camera passes within
## this of its footprint, so a wall that clips the character's shoulder fades too.
static var half_width: float = 14.0
## The side of a cell of the grid the fixed pieces are found by, and how many steps a fade is
## written in (the shader's dither has 16 levels, so a finer step changes nothing on screen).
static var cell: float = 128.0
static var steps: int = 16
## A movable piece (furniture, a door) is checked for a move every this many frames, so a still
## room costs a slice of its pieces a frame rather than all of them.
static var poll_frames: int = 8
## A piece that hangs on a wall (a stain, a menu board) hangs on the wall unit whose footprint,
## grown by this, holds the middle of its thin back; it is looked for each frame it is not found,
## for at most `hang_frames` frames, then the piece is a unit of its own.
static var hang_pad: float = 8.0
static var hang_frames: int = 60
