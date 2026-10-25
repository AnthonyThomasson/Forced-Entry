class_name VehicleConfig
## Vehicles domain tuning, the per-kind rows (a static holder, like GunConfig): one row per kind of
## vehicle in `kinds` and one in `looks`. Distances are px, speeds px/s, accelerations px/s², angles
## rad. Rotation 0 = the nose toward +x; a vehicle's own frame has x forward and y toward its right
## side (its left side is toward -y). The numbers every vehicle shares live in the domain's topic
## holders: `VehicleBoardingConfig`, `VehicleDoorConfig`, `VehicleDriveConfig`,
## `VehicleCollisionConfig` and `VehicleArtConfig`.

## The look of each kind, in the vehicle's frame (x forward, y right; px): how deep the `bumper`s
## are; where the `bonnet` ends at the windscreen's base and the `boot` begins at the rear window's;
## the `roof` panel's front and back x and half width (`roof_half`); the `belt` line's half width
## (the doors' tops: side glass runs between it and the roof); the windscreen's half width at its
## base (`screen_half`) and the rear window's (`rear_half`); the fixed pillars between door glass
## (`pillars`: [back x, front x]); each door's glass (`glass`: door id -> [back x, front x]); a
## door's thickness seen from above (`door_depth`); the `dash`board's [back x, front x] and the
## steering `wheel`'s x; which doors carry a `mirror`; the lamps' half-width spans (`head` / `tail`:
## [inner, outer] |y|) and how long they are.
static var looks := {
	&"car": {
		"bumper": 6.0, "bonnet": 58.0, "boot": -86.0, "roof": Vector2(10, -62), "roof_half": 36.0,
		"belt": 47.0, "screen_half": 45.0, "rear_half": 40.0, "pillars": [Vector2(-25, -20)],
		"glass": {
			&"front_left": Vector2(-20, 58), &"front_right": Vector2(-20, 58),
			&"rear_left": Vector2(-60, -25), &"rear_right": Vector2(-60, -25),
		},
		"a_pillar": 2.5, "door_depth": 7.0, "dash": Vector2(42, 58), "wheel": 33.0,
		"mirror": [&"front_left", &"front_right"], "head": Vector2(33, 47), "tail": Vector2(31, 47),
		"lamp": 7.0,
	},
	&"van": {
		"bumper": 6.0, "bonnet": 100.0, "boot": -125.0, "roof": Vector2(50, -125),
		"roof_half": 53.0, "belt": 56.0, "screen_half": 55.0, "rear_half": 0.0,
		"pillars": [Vector2(20, 26)],
		"glass": { &"front_left": Vector2(28, 100), &"front_right": Vector2(28, 100) },
		"a_pillar": 2.0, "door_depth": 6.0, "dash": Vector2(86, 100), "wheel": 77.0,
		"mirror": [&"front_left", &"front_right"], "head": Vector2(38, 56), "tail": Vector2(40, 59),
		"lamp": 4.0,
	},
}
## One row per kind. `size` is the body (length along x, width along y); `corner` its chamfer;
## `coverage`, `penetration` and `material` its ballistic surface (`get_surface`), `bounce` and
## `friction` its contact with what it strikes. `mass` is the rigid body's, `engine_force` (mass x
## px/s²) drives it up to `top_speed` (the speed full throttle settles at: the push tapers to
## exactly the rolling and drag there), `reverse_force` back to `reverse_speed`; `brake`,
## `handbrake_brake` and `rolling` are decelerations, `drag` the air drag (px/s² per (px/s)²).
## `axle_front` / `axle_rear` are the axles' x, `wheel_size` a wheel's (its look is the kind's
## `looks` row). The front wheels steer up to `steer_angle` (turned there in
## `steer_angle / steer_rate` s); at speed full lock is the angle whose turn asks the front axle for
## `steer_demand` of the grip it holds (1 = as hard as it holds; more scrubs the front wide).
## `grip_front` / `grip_rear` are the most sideways acceleration each axle holds before it slides
## (the rear the more, so at the limit the front lets go first and the vehicle runs wide rather than
## spinning); the handbrake leaves the rear `handbrake_grip` of its grip. `seats` are local points.
## `doors`: `id`, `kind` (`swing` turns about its front hinge, `slide` rolls back along the body,
## `rear` swings out behind about its back corner), `seat` (the seat behind it), `hinge` (where it
## turns, or a sliding door's front edge) and `handle` (where it is pulled, on the body's edge),
## `open_angle` for a swing or rear door.
static var kinds := {
	&"car": {
		"size": Vector2(220, 110), "corner": 14.0, "coverage": 70.0, "penetration": 90.0,
		"material": "metal", "mass": 400.0, "bounce": 0.025, "friction": 0.4,
		"engine_force": 372_000.0, "top_speed": 1280.0, "reverse_force": 160_000.0,
		"reverse_speed": 350.0, "brake": 850.0, "handbrake_brake": 40.0, "rolling": 25.0,
		"drag": 0.00005, "axle_front": 70.0, "axle_rear": -66.0, "wheel_size": Vector2(30, 14),
		"steer_angle": 0.65, "steer_rate": 3.5, "steer_demand": 1.0, "grip_front": 850.0,
		"grip_rear": 1100.0, "handbrake_grip": 0.008,
		"seats": {
			&"driver": Vector2(10, -25), &"passenger": Vector2(10, 25),
			&"rear_left": Vector2(-50, -25), &"rear_right": Vector2(-50, 25),
		},
		"doors": [
			{
				"id": &"front_left",
				"kind": &"swing",
				"seat": &"driver",
				"hinge": Vector2(35, -55),
				"handle": Vector2(-20, -55),
				"open_angle": 1.2,
			},
			{
				"id": &"front_right",
				"kind": &"swing",
				"seat": &"passenger",
				"hinge": Vector2(35, 55),
				"handle": Vector2(-20, 55),
				"open_angle": 1.2,
			},
			{
				"id": &"rear_left",
				"kind": &"swing",
				"seat": &"rear_left",
				"hinge": Vector2(-25, -55),
				"handle": Vector2(-70, -55),
				"open_angle": 1.2,
			},
			{
				"id": &"rear_right",
				"kind": &"swing",
				"seat": &"rear_right",
				"hinge": Vector2(-25, 55),
				"handle": Vector2(-70, 55),
				"open_angle": 1.2,
			},
		],
	},
	&"van": {
		"size": Vector2(260, 125), "corner": 10.0, "coverage": 80.0, "penetration": 90.0,
		"material": "metal", "mass": 700.0, "bounce": 0.025, "friction": 0.4,
		"engine_force": 350_000.0, "top_speed": 880.0, "reverse_force": 210_000.0,
		"reverse_speed": 250.0, "brake": 480.0, "handbrake_brake": 40.0, "rolling": 25.0,
		"drag": 0.00005, "axle_front": 85.0, "axle_rear": -80.0, "wheel_size": Vector2(34, 16),
		"steer_angle": 0.62, "steer_rate": 2.5, "steer_demand": 1.0, "grip_front": 330.0,
		"grip_rear": 420.0, "handbrake_grip": 0.008,
		"seats": {
			&"driver": Vector2(55, -28), &"passenger": Vector2(55, 28),
			&"cargo_left": Vector2(-60, -30), &"cargo_right": Vector2(-60, 30),
		},
		"doors": [
			{
				"id": &"front_left",
				"kind": &"swing",
				"seat": &"driver",
				"hinge": Vector2(80, -62.5),
				"handle": Vector2(28, -62.5),
				"open_angle": 1.2,
			},
			{
				"id": &"front_right",
				"kind": &"swing",
				"seat": &"passenger",
				"hinge": Vector2(80, 62.5),
				"handle": Vector2(28, 62.5),
				"open_angle": 1.2,
			},
			{
				"id": &"side",
				"kind": &"slide",
				"seat": &"cargo_right",
				"hinge": Vector2(20, 62.5),
				"handle": Vector2(14, 62.5),
				"length": 65.0,
			},
			{
				"id": &"rear_left",
				"kind": &"rear",
				"seat": &"cargo_left",
				"hinge": Vector2(-130, -62.5),
				"handle": Vector2(-130, -3),
				"open_angle": 1.65,
			},
			{
				"id": &"rear_right",
				"kind": &"rear",
				"seat": &"cargo_right",
				"hinge": Vector2(-130, 62.5),
				"handle": Vector2(-130, 3),
				"open_angle": 1.65,
			},
		],
	},
}
