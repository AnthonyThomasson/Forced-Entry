class_name CasingConfig
## How a spent casing flies (Projectile domain, `casing.gd`): it leaves the gun's port, hops, falls
## under gravity in the twin 3D space (`SmallFlight`), bounces off the walls and pieces it meets and
## skids to rest on the floor or on top of a piece (a desk, a counter). A `class_name` holder of
## `static var`s, read as `CasingConfig.<name>`; there is no instance and no autoload.

## The casing's size against what it meets (px), and gravity (px/s²).
static var radius: float = 1.2
static var gravity: float = 610.0
## How far (px) it is thrown over level ground (about a metre, as a real shell flies), how high
## (px) it hops off the port, and how fast (rad/s) it turns on the wing: a whole turn either way in
## about a third of a second.
static var eject_distance: float = 40.0
static var hop: float = 6.0
static var spin: float = 19.0
## The share of its speed it keeps bouncing off a surface facing up and off any other (brass rings
## and skips).
static var bounce: float = 0.4
static var wall_bounce: float = 0.4
## Its skid deceleration on a floor or a top (px/s²), and its spin's (rad/s²).
static var friction: float = 600.0
static var spin_friction: float = 60.0
## The most (s) a casing is let fly: past it, it lies where it is.
static var max_time: float = 2.5
