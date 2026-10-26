class_name SoundVehicleConfig
## The vehicles' sounds, for the `Sound` service and SoundVehicles: the engine loop's pitch and
## levels, the skid loop's level and pitch, how fast the loops ease, and the crash bands. A
## `class_name` holder of `static var`s, read as `SoundVehicleConfig.<name>`; there is no instance
## and no autoload.

## The engine loop's pitch with the engine idling at no revs (x) and at the redline (y); the revs
## (`engine_state().rpm`, 0..1) move it between the two, so it climbs through each gear and drops at
## the change.
static var engine_pitch: Vector2 = Vector2(0.85, 2.9)
## How much quieter (dB) the engine is off the throttle than on it, and how much louder at the
## redline than at no revs.
static var engine_load_db: float = 4.0
static var engine_rev_db: float = 3.0
## The skid loop is at full level from this `slip()` up (quieter below it), and pitched up by
## `skid_pitch` at full slip.
static var skid_full_slip: float = 0.4
static var skid_pitch: float = 0.18
## The skid loop is at full level from this vehicle speed (px/s) up, quieter below it (down to a
## quarter); a vehicle with no `speed()` is taken to be at it.
static var skid_full_speed: float = 200.0
## How fast (per second) a loop's pitch and level follow what they track, so a gear change or a
## sudden slide glides.
static var loop_ease: float = 14.0
## A crash at this closing speed (px/s) or faster is `medium`, at the second `heavy` (slower:
## `light`); within its band a crash is louder the faster, by the speed over `crash_speed_ref`
## (clamped).
static var crash_medium_speed: float = 150.0
static var crash_heavy_speed: float = 280.0
static var crash_speed_ref: float = 180.0
