class_name PhysicsImpactConfig
## A hit's shove and the shoved body, for the Physics System (scenes/physics/): the impact impulse,
## its scales and transfer, and how a furniture body settles (damping, CCD). A `class_name` holder
## of `static var`s, read as `PhysicsImpactConfig.<name>`; there is no instance and no autoload.

## Base impulse magnitude at full speed and a head-on hit. Scaled by the hit's speed
## factor (speed / muzzle speed) and by the penetration multipliers below.
static var impulse: float = 2200.0
## Impulse multiplier when the bullet did NOT penetrate (ricochet or blocked/embedded).
static var no_penetration_scale: float = 1.0
## Impulse multiplier when the bullet penetrated (passed through) — less force.
static var penetration_scale: float = 0.5
## Fraction of a flying object's momentum (velocity × mass) handed to the kinematic
## character it strikes. <1 so the shove loses energy. (Rigid-vs-rigid and rigid-vs-wall
## momentum is resolved by the physics engine, not this.)
static var transfer_scale: float = 0.6
## Linear damping applied to furniture bodies — the drag that brings a shove to rest.
static var body_linear_damp: float = 4.0
## Angular damping applied to furniture bodies — the drag that brings a spin to rest.
static var body_angular_damp: float = 4.0
## Enable continuous collision detection on furniture bodies (prevents a fast, light
## object from tunneling through a thin wall, at some CPU cost).
static var body_continuous_cd: bool = false
