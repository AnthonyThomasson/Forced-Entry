class_name PieceBodyConfig
## A free piece of furniture's 3D body (`PieceBody`, #194 furn3d, D13/D14), for the Objects domain:
## how it falls, rests, slides and is judged tipped. A `class_name` holder of `static var`s, read as
## `PieceBodyConfig.<name>` (ADR 0003). Lengths are px, 1 3D unit = 1 px (`BodyHeights`).

## Gravity on a piece (px/s^2): 9.8 m/s^2 at the sim's 42.3 px a metre is 415; 412 is the figure the
## phase-1 spike measured Jolt's pile at.
static var gravity: float = 412.0
## The floor's grip on a sliding piece (Jolt multiplies it with the floor's own): a shoved sofa
## stops within a few px of travel as it did under the 2D drag, a tipped piece does not skate.
static var friction: float = 0.4
## How springy a piece is against a wall or another piece.
static var bounce: float = 0.05
## Linear and angular drag a piece carries on top of the floor's friction (1/s). Light: a falling,
## tipping piece must not float, and friction (not drag) brings a slide to rest.
static var linear_damp: float = 0.4
static var angular_damp: float = 1.2
## How far (degrees) a piece's up axis may lean from the world's before it counts as tipped
## (`PieceBody.tipped`): a piece rocking to rest, or leaning on a wall's skirting, is not.
static var tipped_degrees: float = 25.0
## A tipped piece counts as upright again only under this lean (degrees), so one resting at the
## edge of `tipped_degrees` does not toggle (sit and lie on and off, its footprint cut again).
static var upright_degrees: float = 15.0
## Below this horizontal speed (px/s) the plan drag is not applied (writing a velocity to the engine
## wakes the body, and a piece at rest must be left to fall asleep).
static var drag_floor: float = 6.0
## A piece awake and slower than this (px/s, and rad/s of turn) for `rest_frames` is at rest: the
## engine does not sleep a body that touches a character (a kinematic body moved every frame), so a
## piece resting on one is put to sleep (`PieceBody`).
static var rest_speed: float = 6.0
static var rest_spin: float = 0.2
## How many physics frames of that, none of them with a shove given to it, make a piece at rest.
static var rest_frames: int = 60
