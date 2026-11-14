class_name RenderConfig
## The 3D render's shared tuning (General domain; `camera_rig.gd`, Art's `WorldMirror` and Main's 3D
## view read it, `docs/adr/0013-the-3d-render-mirrors-the-2d-sim.md`). A `class_name` holder of
## `static var`s, read as `RenderConfig.<name>`, so a test or tool can change them (tests restore
## them with `set_static`). The one scale between the 2D sim and the 3D mirror lives here, with the
## camera it is seen through.

## 3D units per 2D pixel: the one scale of the mirror, 2D `(x, y)` -> 3D `(x, 0, y) * unit`.
static var unit: float = 1.0
## The camera's elevation above the ground plane, in degrees. 35.264 is the true isometric angle
## (a 2:1-ish diamond that shows the most floor behind a wall); 26.565 is the 2:1 dimetric
## pixel-art staple and 30 the ticket's "about 30".
static var pitch_degrees: float = 35.264
## The yaw the camera starts at, in degrees: 45 looks at the world's corner. The rig's `yaw` is the
## live value, a property the camera-turn controls set.
static var yaw_degrees: float = 45.0
## How far the camera sits from its focus along its axis, in 3D units. An orthographic camera's
## distance changes nothing on the screen; it only has to clear the tallest thing.
static var distance: float = 900.0
## The clip range of the orthographic camera, tight round `distance` so the depth the outline
## reads keeps its precision.
static var near: float = 300.0
static var far: float = 1500.0
## The internal height of the 3D picture, in pixels, before it is scaled up to the window with
## nearest filtering: 0 renders at the window's own height (one pixel to a screen pixel). The
## pixel post drops it (216 lines is 3x at 1152x648).
static var internal_lines: int = 0
## The canvas layer the 3D view is drawn on: below the HUD (layer 1) and the overlay bar and
## everything over it, under the 2D world's default layer 0 (which is not drawn in 3D mode).
static var canvas_layer: int = -1
