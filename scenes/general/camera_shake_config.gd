class_name CameraShakeConfig
## The camera's explosion shake (General domain, `camera_controller.gd`; `&"explosion"` events). A
## burst adds trauma (0..1) by its kind and how far it is from the camera, and the view is thrown
## about by `max_offset * trauma^2` screen px, trauma draining at `decay` a second. A frag at the
## camera is trauma 1 (`frag`); a burst farther off than its range does not shake it at all. A
## `class_name` holder of `static var`s, read as `CameraShakeConfig.<name>`, like the other config
## holders, so a test or tool can change them (tests restore them with `set_static`).

## Trauma of a frag's blast beside the camera.
static var frag: float = 1.0
## Trauma of a stun's bang beside the camera.
static var stun: float = 0.5
## World px beyond which a frag does not shake the camera.
static var frag_range: float = 1500.0
## The same for a stun.
static var stun_range: float = 900.0
## Screen px of the worst shake (trauma 1).
static var max_offset: float = 28.0
## Trauma lost per second.
static var decay: float = 1.2
## How fast the view is thrown about (rad/s of the fastest wobble).
static var speed: float = 38.0
