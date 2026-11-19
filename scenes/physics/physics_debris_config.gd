class_name PhysicsDebrisConfig
## How a chip knocked off a struck surface flies (scenes/physics/, `debris.gd`): it leaves the hit
## at the hit's height, hops, falls under gravity in the twin 3D space (`SmallFlight`), bounces off
## the walls and pieces it meets and skids to rest on the floor or on a piece's top. A `class_name`
## holder of `static var`s, read as `PhysicsDebrisConfig.<name>`; there is no instance and no
## autoload.

## A chip's size against what it meets (px), and gravity (px/s²), as a dropped item's.
static var radius: float = 1.5
static var gravity: float = 610.0
## How high (px) a chip hops up off the surface before it falls.
static var hop: float = 9.0
## The share of its speed a chip keeps bouncing off a surface facing up and off any other.
static var bounce: float = 0.3
static var wall_bounce: float = 0.4
## Its skid deceleration on a floor or a top (px/s²) and its spin's (rad/s²).
static var friction: float = 600.0
static var spin_friction: float = 60.0
## The most (s) a chip is let fly: past it, it lies where it is (a chip caught in a bounce).
static var max_time: float = 2.5
## Its spin on leaving (turns per second, at most either way).
static var spin_turns: float = 5.0
