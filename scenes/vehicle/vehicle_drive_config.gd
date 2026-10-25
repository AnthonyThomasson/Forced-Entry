class_name VehicleDriveConfig
## Driving (`docs/vehicles.md` V5, V8): the stop and reverse speeds, the tyre solve, the slip and
## skid thresholds, the gears and idle, and the camera's zoom-out. A `class_name` holder of
## `static var`s, read as `VehicleDriveConfig.<name>`; there is no instance and no autoload.
## Speeds are px/s.

## Below this (with no throttle) a vehicle holds still: the tyres' static grip.
static var stop_speed: float = 1.0
## S reverses (W drives forward again) only once the vehicle is this slow the other way.
static var reverse_engage_speed: float = 2.0
## The tyre impulses are solved this many times a frame (both axles together).
static var tyre_iterations: int = 8
## slip() is the sliding speed over at least this speed (so a slow shuffle does not read as a
## slide).
static var slip_reference_speed: float = 30.0
## A `skid` starts above this slip() and stops below the second.
static var skid_start_slip: float = 0.08
static var skid_stop_slip: float = 0.04
## The engine's gears: revs climb through each band of the top speed and drop at the change.
static var gears: int = 4
## Revs at idle, as a share of the redline.
static var idle_rpm: float = 0.18
## While driving, the camera zooms out by this share at the vehicle's top speed.
static var zoom_out: float = 0.35
