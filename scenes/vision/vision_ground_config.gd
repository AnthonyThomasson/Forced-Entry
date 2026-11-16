class_name VisionGroundConfig
## The Vision domain's tuning of the player's view in the 3D render (#193 phase 3): the two masks
## the toon shaders read (`ViewGround`, `ToonMask`). A `class_name` holder of `static var`s, read as
## `VisionGroundConfig.<name>`. The look of the remembered world is `VisionConfig`'s (`grey`,
## `brightness`, `tint`), the feather's width too (`feather`, screen px).

## The live mask's side, texels: a square window of the world about the camera, always this many
## texels whatever the zoom, so a texel is about the same few screen px (at 768 and a 1152 x 648
## screen: 2).
static var live_side: int = 768
## The window's half-width over the radius of the circle round the screen: the slack the camera
## may drift before the window is laid again and redrawn.
static var window_margin: float = 1.25
## The window is laid again when it grew this much wider than the margin asks for (a zoom in left
## it coarse).
static var window_slack: float = 1.8
## The memory's texels per world px, and the most texels a side (the scale drops to fit): the
## memory says only "was ever seen", so a texel is a few px.
static var seen_scale: float = 0.5
static var seen_max_side: int = 2048
## How much light a spot never seen keeps: 0 is black.
static var unseen_brightness: float = 0.0
## Frames after the first cone is painted before the masks are switched on, so the first picture
## never shows a mask that has not been drawn yet.
static var settle_frames: int = 2
