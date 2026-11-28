# Vehicles

A drivable **car** and **van** (issue #54), for the player in a sandbox: get in and out with **Space** by the nearest door, with the
door and the character animated throughout, drive with WASD and the handbrake, crash, shove furniture, run people down, and hear
all of it. Behaviours V1 to V9 are the spec; each has its tests named under it, following the convention of `docs/grenades.md`.
The tests are in `tests/vehicle/` (`tools/run_tests.sh --domain=vehicle`) plus `tests/audio/vehicle_sounds_test.gd`,
`tests/audio/vehicle_door_tone_test.gd`, `tests/general/camera_zooms_out_driving_test.gd` and `tests/general/space_vehicle_key_test.gd`. They drive puppets (no AI) and read
the game only through the drivable contract (`architecture` interface 19), via `tests/_vehicle/vehicle_probe.gd`, which keeps the
plan's numbers as its own consts so a test checks this file and not the code, and its siblings `vehicle_frame_probe.gd` (the
vehicle's frame) and `vehicle_ride_probe.gd` (placing, boarding, getting out and driving). The code is the Vehicles domain (`scenes/vehicle/`,
skill `domain-vehicle`).

All distances are px, speeds px/s and times seconds. The numbers are the Vehicles holders' (`scenes/vehicle/vehicle_*_config.gd`: `VehicleConfig`'s per-kind rows and the
shared `VehicleBoardingConfig`, `VehicleDoorConfig`, `VehicleDriveConfig`, `VehicleCollisionConfig`, `VehicleArtConfig`, `VehicleMeshConfig`). A
vehicle's own frame has x forward (its nose) and y toward its right side.

## Behaviours

### Getting in

**V1. Board by the nearest door.** Space (`Keybinds.INTERACT`, default `KEY_SPACE`, label "Interact (sit, door, vehicle)", rebindable on the
settings page; the old Use key merged into it) picks the door whose handle is nearest the character among those within `door_reach` **60** of it, on a vehicle moving
slower than `board_max_speed` **20**. The car has four doors (front and rear, left and right); the van has two front doors, a sliding
side door on its right and rear double doors. A door that cannot open is skipped for the next nearest that can. A door cannot open when
something solid (a wall, furniture, a character, another vehicle) stands in its swing arc (a sliding door's track) or where the
character would stand to use it, or when the seat behind it is taken. With no usable door, nothing happens. Space is ignored while the
character is dead; in an object interaction it stands up. Space acts on the reachable thing nearest the mouse: a handle in reach is a
candidate beside a chair, a bed and a standing door in reach ahead, and the nearest to the mouse wins, a vehicle by the gap to its outline; a vehicle none of whose doors in reach can open is no candidate, so Space
falls to the next nearest (`docs/doors.md` DR6).
Tests: `vehicle/board_nearest_door` (the front-left door when nearest, the rear-right when nearest, no other door opens),
`vehicle/board_skips_blocked_door` (an armchair in the rear-left door's swing: the front-left door instead),
`vehicle/board_skips_taken_seat` (the driver's seat taken: the rear-left door instead), `vehicle/board_refused_far_or_moving` (75 px
from the nearest handle, or beside a car rolling at 80, nothing opens; beside the stopped car Space boards), `general/space_vehicle_key` (the
action, its default, label, group, settings row and no clash; a `player` pressing Space boards into the driver's seat and gets out again),
`interaction/space_picks_nearest_to_mouse` (with a chair, a door and a car's door in reach, the mouse picks which one Space acts on).

**V2. The seat behind the door.** The character takes the seat behind the door it used: front-left is the driver's seat; front-right is
the passenger's, and a passenger slides across to the driver's seat (`shift_time` **0.6**) when that is empty; the car's rear doors lead
to the rear seats; the van's side and rear doors to its two cargo seats (the side door and the rear-right door both to `cargo_right`).
Only the driver's seat drives (and only once its engine runs); the others ride and can get out.
Tests: `vehicle/passenger_slides_to_driver` (into an empty car by the front right: it ends in the driver's seat and its throttle moves
the car; with a driver it stays a passenger and cannot drive), `vehicle/rear_seat_cannot_drive` (W and D from the rear-left seat: the car
stays put, no engine, no driver; a driver boarding afterwards drives it), `vehicle/van_doors_open_their_way` (each of the side and rear
doors leads to a cargo seat).

**V3. The boarding animation: fluid, never a jump.**
1. The character walks with its own walk cycle (never running) round the body to a stand point just outside the handle, clear of the
   door's swing, turning at `turn_rate` **9** rad/s to face the door over the last stretch. A walk that has not arrived in `walk_timeout`
   **4** (something is in the way), or a vehicle that starts to move, gives the boarding up and frees the seat.
2. The door eases open: a swing door on its front hinge (`VehicleDoorConfig.open_time` **0.35**, eased out); the van's sliding door rolls back
   along the body (`slide_time` **0.5**); its rear doors swing out behind about the back corners.
3. Once the door is open and the character faces it (within `face_tolerance` **0.25** rad), it steps into the gap (eased, its peak
   speed under its walk), turns to face forward and folds down into the seat (`fold_time` **0.5**, eased: the crouch fold carried on
   to seated).
4. The door eases shut behind it (`VehicleDoorConfig.close_time` **0.35**, gathering speed into the slam).

The character's position, facing and fold change continuously every frame (no teleport). Seated, it sits inside the vehicle's body in
3D, under its roof and seen through the tinted, see-through glass. The held item is put
away from the first pose of the ride and taken out again at its end. Boarding and getting out cannot be interrupted except by death: a
character killed on the way falls where it is, its seat is freed and the door stays as it was.
Tests: `vehicle/board_animation_is_continuous` (sampled every frame from the Space press until the door has shut: no frame moves the
character further than a walking step; the facing turns at most 15 rad/s, toward the door and then forward; the door opens in about
0.35 s and eases (at most 0.08 a frame), it is open before the fold starts and shuts only once the character is folded in; the fold
eases from standing to seated (at most 0.05 a frame); the seated character ends inside the body), `vehicle/van_doors_open_their_way` (the side door slides back along the body and never turns; a rear door swings out behind
the van about its back corner and never slides), `vehicle/death_while_boarding` (killed with the door half open: it dies where it
stands, takes no seat, `use.vehicle()` is null, the door stays open), `vehicle/item_stowed_while_riding` (a character holding its pistol
has no item in hand from the fold into the seat until it is out again, then the pistol is back in hand; `inventory.current_item()` is null while it
is posed by the ride).

### Getting out

**V4. Exit.** Space while seated gets out. Above `exit_max_speed` **20**, a driver first brakes the vehicle to a stop and a passenger waits
for it to slow under 20; then the character leaves by its own door if that is clear, else by the nearest clear door whose seat is its
own or empty (sliding across to it first); with none clear it stays in. Getting out is boarding reversed: the door opens, the character
rises out of the seat into the gap and steps out to the stand point beside the door, and the door shuts behind it. A driver leaving cuts
the engine, and a vehicle left rolling slows to a stop under rolling resistance and stays there.
Tests: `vehicle/exit_own_door_else_nearest` (out by the front-left door onto the left side; with both left doors blocked by characters
in their swing, out by the front right onto the right side), `vehicle/exit_blocked_stays_in` (characters in all four doors' swing: Space
opens nothing and the driver stays seated; with the front-right blocker gone it gets out there), `vehicle/exit_at_speed_brakes_first`
(at 70, Space keeps the driver in until the car is under 20, reached in well under the coasting time), `vehicle/driver_exit_cuts_engine_rolls_to_stop`
(the engine starts when the driver sits; the driver gets out at under 20: the engine stops, the car never speeds up, comes to rest and
stays there).

### Driving

**V5. Driving: arcade-real, car-relative.** W is throttle; S brakes, then reverses once the vehicle rolls slower than
`reverse_engage_speed` **2** (likewise W against a reverse); A/D steer relative to the vehicle; the run key (Shift) is the handbrake. The keys are raw while seated: WASD is screen-relative on foot, but a seated driver's keys are the throttle and steer and are never turned by the camera.
The model is a bicycle. The engine pushes from `engine_force / mass` at rest and tapers (by the cube of the speed's share of the top
speed) to exactly the rolling resistance and air drag at the top speed, so full throttle really reaches `top_speed` (**1280** car,
**880** van) and settles there; a lighter throttle settles lower. It launches hard: the car reaches 640 px/s within 1.1 s and the van
440 within 1.4 s, and S from the top speed stops the car within 2.0 s and the van within 2.5 s (`brake` **850** / **480** px/s²). Reverse
runs up to `reverse_speed` **350** / **250**. Rolling resistance and air drag slow it.
Steering is arcade-tight and stays predictable at speed. The steering eases toward the input, full lock in `steer_angle / steer_rate`
s at any speed (the front wheels are turned by that share of the lock at the speed). Full lock is `steer_angle` (**0.65** car, **0.62**
van) while slow, so at about 100 px/s the body's centre turns on a radius of about one body length (car at most 220, van at most 260);
at speed it is the angle whose turn asks the front axle for `steer_demand` **1** of the sideways grip it holds, so full lock at any
speed turns as hard as the tyres hold and no harder: at 800 px/s (above half its top) the car still turns on at most four body lengths. Each axle
cancels its sideways slip up to a grip limit (`grip_front` / `grip_rear`); past it the axle slides. The rear holds more than the front
(weighed by where the axles sit), so at the limit the front lets go first and the vehicle runs wide instead of spinning out (no body
slip angle of 0.5 rad or more without the handbrake); a quick turn-in at speed scrubs the front, and the handbrake leaves the rear axle
`handbrake_grip` **0.8 %** of its grip (a few px/s², as locked tyres hold sideways) so the back end swings out. Below `stop_speed` **1**
with nothing pushing, it holds still. The van is heavier, accelerates slower, has a lower top speed and a wider turn, and slides sooner.
The front wheels are drawn turned by the steering angle, and the brake lights show while the brakes hold. Mouse aim and firing do
nothing from inside (the item is put away).
Tests: `vehicle/drive_throttle_brake_reverse` (W drives along the car's front; S brakes harder than coasting, passes through a stop,
then reverses), `vehicle/steer_turns_car_relative` (D turns neither parked car; W+D turns an east-facing and a west-facing car each to
its own right, W+A to its left), `vehicle/grip_holds_slow_turn` (full steer at about 40 for 2.5 s: the car turns about a pivot in its
rear half, `slip()` under 0.05), `vehicle/handbrake_slides_rear` (at 120 with full steer and the handbrake the body's slip angle toward
the outside of the turn tops 0.2 rad and `slip()` rises; without the handbrake it slides less; measured 0.42 against -0.03 rad),
`vehicle/van_heavier_than_car` (more mass, slower off the line, a lower top speed, a wider circle at 60 with full steer, more slip at
the same 240 px/s; measured circles 246 against 192 px, slip 0.20 against 0.08), `vehicle/wheels_turn_and_brake_lights`
(`wheel_angle()` eases right on D, left on A, back to centre, and less far at speed; `brake_lights()` on while S slows a car rolling
forward, off while coasting or on the throttle), `vehicle/top_speed` (full throttle down a long straight: the car reaches at least 95 %
of 1280 and the van of 880, neither more than 2 % past it; measured 1280 and 880), `vehicle/launch_and_brake` (full throttle from
rest: the car at 640 within 1.1 s, the van at 440 within 1.4 s; S from the top speed: the car stopped within 2.0 s, the van within
2.5 s; measured 0.75 s, 0.97 s, 1.42 s, 1.70 s), `vehicle/turn_radius` (full lock, the radius fitted to the centre's path: at about
100 px/s at most 220 / 260 px, at 800 / 550 px/s (no handbrake) at most 880 / 1040 px with the body slip angle
under 0.5 rad; measured 192 and 246 px, 783 and 943 px, slip angle 0.09 rad at speed), `vehicle/no_fire_from_inside` (a seated driver
and passenger click the trigger of a loaded pistol: no shot, hit or shot sound, no ammo spent; on foot the same click fires).

### Collisions

**V6. Collisions: full physical.** The vehicle is a free 3D body locked upright (`VehicleBody`, a `RigidBody3D` in the twin space: it
cannot roll or pitch, it turns about up and slides on the floor; its mass, its grip and its driving model are the 2D body's) and its
2D body is a plain `Node2D` plan handle (no 2D shape or layer) the twin space writes from it. It is the same vehicle: the
numbers below hold.
- Walls stop it; it loses most of its speed on the impact (`bounce` **0.025**: a crash at the top speed rebounds slower than rolling
  resistance stops within a second).
- The 3D engine caps a body's speed at 5000 px/s (`max_linear_velocity`, global): above the car's top speed (1280), so no raise.
- Furniture is a free 3D body too: the engine solves the two (the pushable contract) and the vehicle carries on. The bumper's blow
  adds to that at the height it meets a piece (`strike_height`, the sill and half the bumper: 14.5 px for a car): a piece first met
  faster than `crash_min_speed` is struck with `strike_share` **0.4** of the closing speed times its mass there, so a tall thin
  piece (a bookshelf) is kicked low and goes over, and a low heavy one (a sofa) only slides on, upright. The blow is momentum **added on top of** the engine's own solve of the contact (the car does not
  lose it): energy put in on purpose so a strike tips a tall piece, tuned by `strike_share`. A vehicle cannot be tipped:
  a blow at any height turns it about up or slides it. Only its roll and pitch are locked, not its height: gravity and the floor
  hold it down, and a piece tipped under the hull could lift it a little (it comes back down; not asserted).
- A character struck is knocked back (`apply_impulse`) and takes `take_damage(health x (closing − 90) / (300 − 90))`: nothing below
  `harm_min_speed` **90**, death at `harm_kill_speed` **300** or faster. One run-in is one blow: a character struck again within
  `rehit_time` **0.5** s of the last time it was against the vehicle is shoved on but not hurt again. A dead body is rolled over, and
  lies on the floor under the vehicle.
- The vehicle does not collide with a character in 3D (it overlaps the character's cylinder), so it is never stopped dead by one:
  what it is struck at, the shove and the harm are judged by shape queries after each step (never by the engine's contact events).
  It loses only the momentum the character takes, and what the character is pressed
  against. What stands in front of it is a pile: the character struck and the pieces of furniture or other characters it is pressed
  against (each within `pile_gap` **4** px along the push, at most `pile_depth` **4** bodies), or a piece pressed against a character.
  The vehicle and the pile meet as two bodies, the pile's mass all its members' (a character bounces off with `harm_bounce` **0.4** of
  the closing speed on the first touch, a piece with the vehicle's own bounce, and none while the vehicle keeps pushing), and every
  member is shoved on at the pile's new speed: in the open the car keeps about 87 % of its speed, against a character pinned on a
  heavy armchair (or an armchair pressed against a character) about 70 %, and it shoves the chair on.
- A character pinned against a wall (or anything else not pushable) is crushed: it takes the hit's harm and the vehicle stops as on a
  wall, posting a `crash`. A character behind a piece the vehicle strikes takes the blow through it, struck at the closing speed less
  the share the pieces in between took (`closing x vehicle mass / (vehicle mass + their mass)`): a person pushing a chair into someone
  hurts nobody; only a vehicle does.
- Each new impact faster than `crash_min_speed` **60** posts a `vehicle` `crash` event with its closing speed and the struck material
  (`""` for a wall), or a `bump_character` for a character.
- Bullets hit it like furniture: `get_surface()` is metal, penetration **90**; `take_hit` dents it
  (`Deformable`, at most 3 px deep, the last 24 dents kept), throws debris and shoves it at the hit. It is never destroyed, and its
  occupants are not hit through the body.
Tests: `vehicle/vehicle_is_a_locked_upright_3d_body` (the vehicle's truth is a `RigidBody3D` locked about the horizontal axes: a huge
shove at its roof height turns it and slides it, never leans it), `vehicle/car_tips_a_bookshelf_but_slides_a_sofa` (a car rolling at 500
into a bookshelf lays it over, into a sofa only slides it), `vehicle/drive_script_matches_the_2d_body` (a fixed input script's path,
heading and speed within 3 px, 0.01 rad and 2 % of what the 2D body did; the 3D body is read), `vehicle/vehicle_started_before_its_3d_body_drives` (a car started the
frame it is built drives at once and may not sleep), `vehicle/vehicle_rolled_to_a_stop_goes_to_sleep` (a stopped vehicle, engine off, sleeps: the step writes a
velocity only when it changed), `vehicle/car_strikes_the_right_bodies_among_a_crowd` (32 chairs along the flanks do not crowd the four characters ahead out of the strike
query), `vehicle/vehicle_gravity_is_the_furniture_gravity`, `vehicle/crash_into_wall_stops` (driven flat out into a wall: a crash event with the impact speed, the kind and a material; most
of the speed lost; it stays this side of the wall and stops), `vehicle/pushes_furniture` (an armchair is shoved well along the car's
path, the car keeps moving, a crash names fabric), `vehicle/hits_character_damage_by_speed` (empty cars rolling at 60, midway between
the two speeds, and past 300: shoved and unhurt, hurt and alive, dead), `vehicle/pinned_character_crushed` (empty cars at 200 into a
character pinned on a heavy armchair, one pinned on the wall, one in the open and one behind the armchair: the pinned ones take at least
the open hit's harm and the shielded one half of it; 0.1 s after the touch the car keeps 30 % / 70 % / 50 % of its speed (pinned / open /
shielded) and shoves the chair; on the wall it posts a crash; measured harm 25.4 open, 25.4 pinned on the chair and on the wall, 17.6
behind the chair; kept 130 / 168 / 139 px/s, the chair shoved 63 and 57 px), `vehicle/bullet_dents_vehicle` (a metal surface with
60+ and penetration 80+, a recorded dent, debris; six more rounds leave it standing).

### Presentation

**V7. Sounds**, synthesized like every other sound (Audio domain, `domain-audio`):
- the ignition (the starter cranking, the engine catching) when a driver sits down;
- one looping engine per running vehicle, its pitch following the revs (which climb through four gears and drop at each change) and its
  level the throttle and revs, idling when stopped and cut when the driver leaves; the van's is deeper than the car's;
- a door in a reload's register, mechanical and low, with no creak or ring: on opening the handle's click, the latch letting go with a
  knock and the soft thump of the door coming off its seal; on shutting the slam, the door's weight thumping home, the latch clicking shut
  and the trim knocking; the van's are lower and heavier, its sliding door rolls on its runners into the stop and shuts with a heavy thunk;
- a looping tyre squeal while the vehicle slides, as loud as the slide;
- a crash crunch by the struck material and the closing speed (light under 150, medium, heavy from 280, louder within its band the
  faster), and a thud on a character struck.
Tests: `audio/vehicle_sounds` (boarding the car: door open and close, ignition, the engine loop rising in pitch with speed and cut on
exit; a handbrake slide squeals; the van's slide door rolls; a fast crash louder than a slow one; a car striking a character thuds; the
vehicle profiles are in the bank; the van's engine is the deeper), `audio/vehicle_door_tone` (every take of every `door/` profile is no
brighter than the brightest reload take and keeps over 0.75 of its energy under 300 Hz; measured: car open 0.80, car close 0.82, van open
0.87, van close 0.86, van slide open 0.82, van slide close 0.86), `audio/bank` (every profile, the vehicles' included, renders a sane clip
within the library's time budget).

**V8. Camera.** The camera follows the character, which the seat carries. While it is aboard a moving vehicle the zoom eases out with the
vehicle's speed (`VehicleDriveConfig.zoom_out` **0.35** at the top speed, in proportion below it) and back in as it slows.
Tests: `general/camera_zooms_out_driving` (the on-foot zoom while parked, zoomed out at 35 % of the car's top speed and further at 70 %,
back to the on-foot zoom once stopped, still following the driver).

**V9. Sandbox only.** `sandboxes/vehicle_sandbox.gd` ("Vehicle yard", in the browser's Sandboxes section) has the player (with a
pistol, to dent the bodywork), a car and a van, an open concrete yard with walls, furniture to shove and three dummies. Nothing in Main,
World-Gen or the match uses vehicles; the garage's static `car` furniture is unchanged; the AI ignores vehicles and the nav map does not
carve them (an NPC sees a parked one only as a solid body). Not a behaviour a test asserts: outside the Vehicles domain, only the
character and its player controller, the camera, Audio (through the events' `vehicle`), the Testing domain and the sandbox reach a
vehicle; nothing under
`scenes/main.gd`, `scenes/worldgen/`, `scenes/ai/` or `scenes/navigation/` does.

## How the rules are enforced

- **Vehicles** (`scenes/vehicle/`): `VehicleConfig` (one `kinds` and one `looks` row per kind) and the topic holders (the shared numbers), `vehicle.gd` (the body, the
  contract, the hittable, the events), `vehicle_cabin.gd` (seats and doors), `vehicle_contacts.gd` (contacts and harm),
  `vehicle_drive.gd` (the bicycle, the drive intent, the engine and the skids), `vehicle_door.gd` (the open
  amount, the pose, the stand point, the blocked check), `vehicle_boarding.gd` (the ride's phase machine), `character_vehicle_use.gd` (the
  character's component), `art/` (the painters and the 3D meshes: `art/vehicle_mesh*.gd`, `VehicleMeshConfig`).
- **Character**: the forwards `use.try_interact()` (Space: a chair, a door or the vehicle, `docs/doors.md` DR6), `use.vehicle()`, `use.is_in_vehicle()`, the ride API `use.set_ride_pose` / `use.end_ride`, `use.is_busy()`
  over the ride, `inventory.current_item()` null while posed, `_die` abandoning the ride. **General**: `Keybinds.INTERACT` and the camera's zoom
  out. **Audio**: the `vehicle`, `engine` and `skid` topics, the profiles and the loops. **Testing**: `TestSetup.vehicle`, `t.vehicle`,
  the puppet's `use()` and `drive(throttle, steer, handbrake)`.
- **The tests reach all of it duck-typed** (`has_method`, `call`, groups, the Vehicles holders read by name), so a read that is missing fails a
  `require` instead of a script error.

## Numbers

| | Car | Van |
|---|---|---|
| Body | 220 x 110, mass 400 | 260 x 125, mass 700 |
| Engine, top speed | 372000 (930 px/s² from rest), 1280 | 350000 (500 px/s²), 880 |
| Reverse | 160000 up to 350 | 210000 up to 250 |
| Brake / handbrake / rolling (px/s²), drag | 850 / 40 / 25, 0.00005 | 480 / 40 / 25, 0.00005 |
| Bounce, friction | 0.025, 0.4 | 0.025, 0.4 |
| Steering: lock, rate, demand at speed | 0.65 rad, 3.5 rad/s, 1 | 0.62 rad, 2.5 rad/s, 1 |
| Grip front / rear (px/s²), handbrake | 850 / 1100, 0.8 % | 330 / 420, 0.8 % |
| Surface | metal, penetration 90 | metal, penetration 90 |
| Doors | four swing doors | two front swing doors, a slide door (right), two rear doors |

Shared: reach 60; board and exit below 20; doors 0.35 open and shut, a slide 0.5; fold 0.5; slide across 0.6; turn 9 rad/s; harm from 90,
lethal at 300, one blow per run-in (0.5 s); a pile's bodies within 4 px, at most 4; crash from 60; camera zoom out 0.35 at top speed.

## This game's own rules

Everything numeric; the bicycle model itself (no suspension, no gearbox beyond the engine sound's rev bands, no engine braking beyond
rolling and drag); the static grip below 1 px/s; the handbrake as the run key; boarding only below 20 and getting out braking to a stop
first; the slide across from the passenger seat; the steering lock at speed set by the front grip; harm proportional to the closing
speed between 90 and 300 with a fixed bounce, one blow per run-in; a character and what it is pressed against struck as one pile; harm
through a piece only from a vehicle; a dead body rolled over; no destruction; the sandbox only.

## Not modelled

The AI using, perceiving or pathing round vehicles (no nav carve); vehicles in Main, World-Gen or a match; vehicle destruction, tyres
shot out, occupants hit through the body or the glass; shooting from a vehicle; a horn; headlights at night; damage to the vehicle from
crashes (only bullets dent it); a locked or jammed door.
