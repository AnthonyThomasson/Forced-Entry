class_name CameraConfig
## The camera's follow, framing, zoom and hand pan (General domain, `camera_controller.gd`). A
## `class_name` holder of `static var`s, read as `CameraConfig.<name>`, like the other config
## holders, so a test or tool can change them (tests restore them with `set_static`). The explosion
## shake is `CameraShakeConfig`.

## Higher = slower, smoother follow (the camera lerps by 1/follow_speed each frame).
static var follow_speed: float = 8.0
## How far toward the mouse to lead the camera (world units).
static var look_ahead_distance: float = 60.0
## Distance from screen center the mouse must reach to trigger look-ahead (0-1 fraction of screen).
static var look_ahead_threshold: float = 0.6
## Framing group: extra world-space padding kept around the framed combatants so they aren't flush
## to the screen edge.
static var frame_margin: float = 160.0
## Clamp for the fit-to-combatants zoom (Camera2D zoom: larger = more zoomed in).
## Most zoomed-out the framing is allowed to get.
static var min_zoom: float = 0.4
## Most zoomed-in the framing is allowed to get.
static var max_zoom: float = 2.0
## Each wheel notch scales the zoom by this factor (> 1; larger = bigger steps).
static var zoom_step: float = 1.1
## Notches of zoom per unit of a trackpad's two-finger scroll (its pan-gesture delta).
static var trackpad_zoom_sensitivity: float = 0.03
## Limits on the zoom the wheel can reach, whatever the automatic zoom is.
## Most zoomed-out.
static var wheel_min_zoom: float = 0.25
## Most zoomed-in.
static var wheel_max_zoom: float = 4.0
## Hand-pan speed, in screen pixels per second (so it feels the same at any zoom).
static var pan_speed: float = 700.0
## Width (px) of the screen-edge band where the mouse pans the camera; 0 turns edge panning off.
static var edge_pan_margin: float = 24.0
## Seconds without camera input before a hand-steered framing camera returns to automatic framing.
static var manual_hold: float = 5.0
