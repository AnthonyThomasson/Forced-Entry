class_name VehicleBoardingConfig
## Getting in and out of a vehicle (`docs/vehicles.md` V1-V4): the door reach, the speeds boarding
## and exiting allow, the fold and the shift, and the walk and step to the door. A `class_name`
## holder of `static var`s, read as `VehicleBoardingConfig.<name>`; there is no instance and no
## autoload. Distances are px, speeds px/s, angles rad.

## E picks a door whose handle is within this of the character.
static var door_reach: float = 60.0
## Boarding only while the vehicle moves slower than this.
static var board_max_speed: float = 20.0
## E while seated above this first brakes the vehicle to a stop (a driver) or waits for it (a
## passenger).
static var exit_max_speed: float = 20.0
## The fold down into the seat (and the rise out of it) takes this long.
static var fold_time: float = 0.5
## The slide across the bench to another seat takes this long.
static var shift_time: float = 0.6
## The step into and out of the gap is taken at this share of the character's walk speed (its peak
## is 1.5x the average).
static var step_pace: float = 0.55
## The shortest step into or out of the gap (s).
static var step_min_time: float = 0.2
## How fast (rad/s) the character turns while it boards or gets out.
static var turn_rate: float = 9.0
## Facing within this (rad) of the handle counts as facing the door, so the step in can begin.
static var face_tolerance: float = 0.25
## Giving up on a walk to the door that has not arrived in this long (s): something is in the way.
static var walk_timeout: float = 4.0
## The walk round the body keeps this far (px) beyond the character's radius off it.
static var walk_margin: float = 2.0
