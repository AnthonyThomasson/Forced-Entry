class_name PhysicsRagdollConfig
## The ragdoll solver's tuning (scenes/physics/ragdoll.gd: a 3D point-mass body falling onto the
## floor plane): gravity, steps, drag, floor contact, the push and speed caps, joint friction and
## sleep. A `class_name` holder of `static var`s, read as `PhysicsRagdollConfig.<name>`; there is
## no instance and no autoload.

## Gravity pulling ragdoll points toward the floor (px/s²): 9.8 m/s² at ~62 px per metre (a
## character's 28 px shoulders ≈ 0.45 m).
static var gravity: float = 610.0
## Sub-steps per physics frame, and constraint passes per sub-step: more = stiffer joints.
static var substeps: int = 2
static var iterations: int = 6
## Air drag on every point (1/s).
static var air_drag: float = 0.3
## Sliding deceleration of a point touching the floor (px/s²): high, so planted feet hold and the
## body topples over them instead of skating.
static var floor_friction: float = 2400.0
## Fraction of a point's downward speed kept as bounce when it strikes the floor.
static var floor_bounce: float = 0.15
## Hardest the bones and joint limits may speed a point up (px/s²), and a cap on any point's
## speed (px/s): together they keep a fight between constraints and the floor from flinging the
## body.
static var max_push: float = 1800.0
static var max_speed: float = 700.0
## How fast a limited joint's child is pulled toward its joint's velocity (1/s): limbs swing as
## heavy, loose parts rather than whipping.
static var joint_friction: float = 4.0
## A body sleeps once every point has stayed under this speed (px/s) for `sleep_time` (s),
## or after `max_time` (s) regardless.
static var sleep_speed: float = 5.0
static var sleep_time: float = 0.4
static var max_time: float = 5.0
