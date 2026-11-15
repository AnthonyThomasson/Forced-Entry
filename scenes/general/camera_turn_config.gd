class_name CameraTurnConfig
## The 3D camera's quarter turns (General domain, `camera_rig.gd`; #193 phase 2b G16). A
## `class_name` holder of `static var`s, read as `CameraTurnConfig.<name>` (ADR 0003), so a test may
## `set_static` them.

## A camera-turn key (Q / E) turns the camera this many degrees, about its focus: a quarter, so it
## rests at north, east, south or west. Pressed again while it turns, it queues another quarter.
static var step_degrees: float = 90.0
## The turn's easing, in degrees a second: it runs at up to `speed_degrees`, slows as the angle
## left shrinks (that many times a second of it, `ease_rate`) and never crawls slower than
## `min_speed_degrees`, so a quarter takes about 0.4 s and ends exactly on the cardinal.
static var speed_degrees: float = 540.0
static var ease_rate: float = 10.0
static var min_speed_degrees: float = 60.0
