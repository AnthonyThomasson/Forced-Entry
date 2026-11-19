class_name VehicleCollisionConfig
## A vehicle's collisions (`docs/vehicles.md` V6): the harm to a character struck, the pile, the
## re-hit time, the crash threshold and the body's dents. A `class_name` holder of `static var`s,
## read as `VehicleCollisionConfig.<name>`; there is no instance and no autoload. Distances are
## px, speeds px/s.

## A character struck slower than this (closing speed) is shoved, not hurt.
static var harm_min_speed: float = 90.0
## A character struck at this closing speed or faster is killed; between the two, hurt in
## proportion.
static var harm_kill_speed: float = 300.0
## How much of the closing speed a struck character bounces off with (0 = carried along at the
## vehicle's speed).
static var harm_bounce: float = 0.4
## A pile in front of the vehicle (a character struck and what it is pressed against, or a piece
## pressed against a character): bodies this close (px) along the push press on one another, at most
## this many are followed, and a piece's characters are looked for within this far (px) of it.
static var pile_gap: float = 4.0
static var pile_depth: int = 4
static var pile_reach: float = 150.0
## A character struck again within this long (s) of the last time it was in a pile is the same
## run-in: shoved on, not hurt again.
static var rehit_time: float = 0.5
## An impact faster than this posts a crash (or a bump on a character).
static var crash_min_speed: float = 60.0
## A free piece of furniture the vehicle first meets faster than `crash_min_speed` is struck at the
## height of the bumper (`strike_height`, from the vehicle's `VehicleMeshConfig.heights`: the sill
## and half the bumper): the blow is `strike_share` of the closing speed times the piece's mass, so
## a tall thin piece is kicked low and leans, a low heavy one is only slid (the contact the physics
## engine then solves carries it on).
static var strike_share: float = 0.4
## The pull toward the floor in the 3D space (px/s²): the same as a piece of furniture's, which
## this domain may not read (`PieceBodyConfig.gravity`, Objects).
static var gravity: float = 412.0
## The body's dents: deepest (px) and how many are remembered.
static var dent_max_depth: float = 3.0
static var dent_max_impacts: int = 24


## How high (px above the floor) a vehicle of `kind` strikes a piece: the middle of its bumper.
static func strike_height(kind: StringName) -> float:
	var row: Dictionary = VehicleMeshConfig.heights[kind]
	return float(row["sill"]) + VehicleMeshConfig.bumper_height * 0.5
