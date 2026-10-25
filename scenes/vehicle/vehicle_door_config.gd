class_name VehicleDoorConfig
## A vehicle door's motion (scenes/vehicle/vehicle_door.gd, `docs/vehicles.md` V1-V4): the swing
## and slide times, the slide's pop, the stand point and the swept clearance. A `class_name` holder
## of `static var`s, read as `VehicleDoorConfig.<name>`; there is no instance and no autoload.
## Distances are px, times s.

## A swing or rear door eases open in this long (ease-out) and shut in this long (it gathers speed
## into the slam).
static var open_time: float = 0.35
static var close_time: float = 0.35
## A sliding door rolls open and shut in this long.
static var slide_time: float = 0.5
## How far (px) a sliding door stands out from the body while it rolls.
static var slide_pop: float = 3.0
## The stand point beside a door is this far (px) out from the body, beyond the character's radius.
static var stand_out: float = 16.0
## The swept door (or the stand point) must clear what stands near it by this much (px).
static var clearance: float = 3.0
