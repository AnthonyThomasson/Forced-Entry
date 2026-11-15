class_name RenderConfig
## The 3D render's shared tuning (General domain; `camera_rig.gd`, Art's `WorldMirror` and Main's 3D
## view read it, `docs/adr/0013-the-3d-render-mirrors-the-2d-sim.md`). A `class_name` holder of
## `static var`s, read as `RenderConfig.<name>`, so a test or tool can change them (tests restore
## them with `set_static`). The one scale between the 2D sim and the 3D mirror lives here, with the
## camera it is seen through.

## 3D units per 2D pixel: the one scale of the mirror, 2D `(x, y)` -> 3D `(x, 0, y) * unit`.
static var unit: float = 1.0
## The camera's elevation above the ground plane, in degrees. 80 is the near top-down view of the
## 2D game (#193 phase 2b, G11): the ground is foreshortened to sin(80) = 0.985 and the side of a
## wall or a body shows as a thin sliver, so the 2D painters' top views are what the picture shows.
## 90 would show no side at all; 35.264 was the isometric angle of phases 1 and 2.
static var pitch_degrees: float = 80.0
## The yaw the camera starts at, in degrees: 0 is the 2D view's own orientation (north, -y, up the
## screen). The rig's `yaw` is the live value; the camera-turn keys step it a quarter at a time
## (`CameraTurnConfig.step_degrees`), so it rests at 0, 90, 180 and 270 only.
static var yaw_degrees: float = 0.0
## How far the camera sits from its focus along its axis, in 3D units. An orthographic camera's
## distance changes nothing on the screen; it only has to clear the tallest thing.
static var distance: float = 900.0
## The clip range of the orthographic camera, tight round `distance` so the depth the outline
## reads keeps its precision.
static var near: float = 300.0
static var far: float = 1500.0
## Whether the picture's pixel is the art's pixel times the zoom (#193 phase 2b, G13): the picture
## is drawn `art_pixel` 2D px to a picture pixel and shown with nearest filtering, a whole number
## of screen pixels to a picture pixel (the zoom, 1 to 3 in the 3D view: the camera controller
## snaps it to whole steps), so one pixel of a 2D painter's art is one picture pixel times the zoom
## and its texels stay crisp. Off draws a picture pixel to a screen pixel whatever the zoom.
static var texel_match: bool = true
## The 2D pixels one art pixel covers (`ArtCanvasConfig.pixel_size`, which a test pins it to;
## General cannot read Art).
static var art_pixel: float = 1.0
## The canvas layer the 3D view is drawn on: below the HUD (layer 1) and the overlay bar and
## everything over it, under the layers the flat overlays draw on (and the 2D world's default
## layer 0, which is not drawn in 3D mode).
static var canvas_layer: int = -2
## The canvas layers the player's view and the debug overlays draw on in 3D mode (`GroundLayer`):
## flat on the ground plane, over the 3D view and under the HUD. The view's composite is under the
## overlays, as in 2D.
static var vision_layer: int = -1
static var overlay_layer: int = 0
## How dark the view composite lays the ground outside the player's cone in 3D mode, 0 (not at all)
## to 1 (black, as in 2D): the 2D memory is not drawn there, so until the lighting and vision jobs
## draw it from the 3D scene the unseen ground is only dimmed, to stay readable. Read when the
## view's composite is built, so a change applies from the next match.
static var unseen_dim: float = 0.6
