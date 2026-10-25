class_name VehicleArtConfig
## How a vehicle is painted (`docs/vehicles.md` V3): the tyres', hubs', glass, cabin, trim, cargo
## floor's and lamps' colours, the door glass's fade and the redraw steps; each kind's proportions
## are its `VehicleConfig.looks` row. A `class_name` holder of `static var`s, read as
## `VehicleArtConfig.<name>`; there is no instance and no autoload.

## The tyres' rubber and the hubs.
static var tyre_color: Color = Color(0.1, 0.1, 0.11)
static var hub_color: Color = Color(0.5, 0.51, 0.53)
## The glass: tinted, and see-through (its alpha), so a seated occupant shows under it.
static var glass_color: Color = Color(0.3, 0.42, 0.5, 0.42)
## The cabin's floor, the seats, and the black trim (bumpers, rubbers, dashboard, grille).
static var interior_color: Color = Color(0.17, 0.16, 0.16)
static var seat_color: Color = Color(0.27, 0.25, 0.23)
static var trim_color: Color = Color(0.12, 0.12, 0.13)
## A van's cargo floor (plywood over the metal).
static var cargo_floor_color: Color = Color(0.45, 0.37, 0.27)
## The lamps: headlights, and the tail lights dark and lit (braking), with the glow a lit one throws
## on the ground.
static var headlight_color: Color = Color(0.93, 0.92, 0.82)
static var tail_off_color: Color = Color(0.46, 0.09, 0.08)
static var tail_on_color: Color = Color(1.0, 0.2, 0.13)
static var brake_glow: Color = Color(1.0, 0.15, 0.08, 0.3)
## Door glass fades out over the first this share of the door's opening (the window goes with the
## door).
static var glass_fade: float = 0.3
## The drawing is repainted when the wheels turn or a door moves this much (rad, open share), or the
## body this much (rad).
static var redraw_step: float = 0.02
static var redraw_turn_step: float = 0.01
