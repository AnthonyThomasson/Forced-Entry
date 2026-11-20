---
name: domain-vehicle
description: Use when editing scenes/vehicle/ or working on cars and vans: driving feel, getting in and out, doors and seats, collisions and harm, vehicle art.
---

# Vehicles domain

A drivable **car** and **van** (one scene each, inheriting `vehicle.tscn`). Only `sandboxes/vehicle_sandbox.gd` and the tests (`TestSetup.vehicle`) place them. Main, World-Gen and the match never do, the nav map does not carve them, and the AI sees a parked one only as a solid body. The spec, rule by rule with its tests, is `docs/vehicles.md` (V1 to V9, with the numbers). Tests: `tests/vehicle/`, probed through `tests/_vehicle/` (`vehicle_probe.gd`, `vehicle_frame_probe.gd`, `vehicle_ride_probe.gd`; `domain-testing`) plus `tests/audio/vehicle_*`, `tests/general/camera_zooms_out_driving_test.gd`, `tests/general/space_vehicle_key_test.gd`.

```
player_controller (Space) ─▶ Character.use.try_interact (when a vehicle's door is the thing nearest the mouse: `use.interact_target()`) ─▶ CharacterVehicleUse ─▶ vehicle.board(character, door) ─▶ VehicleBoarding (the ride)
VehicleBoarding ──(movement.move_input / aim_point, use.set_ride_pose, use.end_ride)──▶ Character;  seated driver: move_input / run_input ─▶ vehicle.drive_input
VehicleBody._integrate_forces (3D) ─▶ drive.step (VehicleDrive), contacts.remember   /   vehicle._physics_process ─▶ contacts.read (VehicleContacts: shape queries) ─▶ crash events, characters struck
```

## Files

| File | Role |
|---|---|
| `vehicle.gd` | Root `Node2D`, the plan handle (no `class_name`; group `vehicles`) of the 3D body that leads it: set-up, the old rigid body's reads and writes answered by that body (`linear_velocity`, `angular_velocity`, `sleeping`, `apply_impulse`, `get_mass`), the drivable contract (interface 19), the hittable contract, its parts (`cabin`, `drive`, `contacts`, `row`) and `post`, through which every `vehicle` event goes. |
| `vehicle_body.gd` (`VehicleBody`) | The vehicle's truth: a `RigidBody3D` locked upright in the twin space (`TwinSpace.leader_of`), the drive stepped in its `_integrate_forces` in plan space, `push` / `plan_velocity` / `wake` as a piece's. |
| `vehicle_cabin.gd` (`VehicleCabin`) | Doors, seats and whose ride is whose (`take_seat` starts a ride, `release` ends it). |
| `vehicle_drive.gd` | The bicycle model, stepped in `_integrate_forces`; the drive `intent`, engine, skids. `tyre_solve.gd` (`TyreSolve`) is one step's sideways solve. |
| `vehicle_contacts.gd` (`VehicleContacts`) | Contacts and harm (V6): `read`/`remember` around the drive's step, `apply` in `_physics_process`. |
| `vehicle_door.gd` | One door: eased open amount, pose, stand and entry points, `is_clear`. |
| `vehicle_boarding.gd` | One character's ride: a timed phase machine (`Phase`, `Pose`), from Space to the last step out. |
| `character_vehicle_use.gd` | The character's component (`CharacterUse.attach`): picks the door, steps the ride, abandons it on death. |
| `vehicle_twins.gd` (`VehicleTwins`) | The builder of the `VehicleBody` for General's twin space (29): the outline from the ground to `VehicleMeshConfig.heights[kind].belt` and the cabin (`looks.roof`, `roof_half`) on to the roof, on `PhysicsLayers.TWIN_VEHICLE`; dents are not in it. One source for heights: `VehicleMeshConfig.heights` (the prop car and the mirror read it). Tests: `tests/vehicle/twin_vehicle_follows_test.gd`, `vehicle_heights_are_one_source_test.gd`. |
| `art/` | The painters and the 3D mesh: read `art.md` before touching them. |
| `vehicle_config.gd` (`VehicleConfig`) | `kinds` row per kind (`car`, `van`: size, mass, engine, axles, grips, `seats`, `doors`) and `looks` row per kind (the painters' proportions). Shared numbers: `VehicleBoardingConfig`, `VehicleDoorConfig`, `VehicleDriveConfig`, `VehicleCollisionConfig`, `VehicleArtConfig`, `VehicleMeshConfig` (the 3D heights and part sizes). |

**Frames.** Rotation 0 = nose toward +x; the vehicle's own frame has x forward, y to its right. Every door, seat, axle and `looks` entry is in that frame. Art is painted in Art's canonical frame (front toward +y) and drawn turned by `BODY_TURN`.

## Body and driving (V5)

- The collider is one convex polygon of `outline()`; the `Deformable` child records dents but nothing rebuilds the collider from them. `can_sleep` is off while the engine runs.
- The 3D body's `_integrate_forces` runs `drive.step`, which writes the velocities (plan space `(x, z)`, the turn about up; its vertical part is the floor's) for the next step from the `intent` (`throttle`, `steer`, `handbrake`, `brake`: from `drive_input`, driver only and engine running, or `drive.brake_input`, which holds to a stop and never reverses).
- **Steering lock is derived, not tuned.** Slow, full lock is `steer_angle`; at speed it is the angle that asks the front axle for exactly the sideways grip it holds (`lock(row, speed)`), so full lock never plows or spins. `steer_share` eases at `steer_rate / steer_angle` per second, so full lock takes the same time at any speed.
- **Throttle tapers to the top speed.** `_engine` falls with the cube of the speed share to exactly rolling + drag at `top_speed`, so full throttle settles there whatever the drag.
- **Balance.** The rear limit is kept above the front's, so at the limit the front slides first (understeer). A weaker rear would spin on a fast turn. The handbrake leaves the rear `handbrake_grip` of its grip: it must stay a few px/s², as locked tyres still hold sideways; more damps the tail's swing and `vehicle/handbrake_slides_rear` fails.
- Under `stop_speed` with no push the velocities are zeroed (static grip).

## Doors, seats and the ride (V1 to V4)

- Door kinds: `swing`, `slide`, `rear` (swings out behind). The van's side and rear-right doors share the seat `cargo_right`: taking one makes the other's seat taken.
- The open amount is linear in time and read eased (`amount()`), a close gathering speed into the slam. `update(delta)` returns true on the frame a closing door shuts, and the vehicle posts the close then.
- `is_clear(vehicle, rider, radius)` asks the twin space (29) for the swept sector or slide track, then the rider's cylinder at the stand point; anything solid blocks.
- **Picking the door** (`CharacterVehicleUse.try_use_vehicle`, reached through `use.try_interact()` when a vehicle's door is what Space acts on: `use.interact_target()` weighs `nearest_door_distance(aim)`, the gap from the mouse to the outline of a vehicle with a door it `can_board` or `INF`, against the objects and a house door in reach, interfaces 8, 24): seated → `vehicle.exit`; on foot → the doors of every vehicle in the group `vehicles` within `door_reach` and moving slower than `board_max_speed`, nearest first; those it `can_board` (the same checks as `board`, changing nothing), the first whose `board(character, door)` returns a ride wins. `board` refuses at speed, a taken seat, a character already riding or a blocked door, and adds a collision exception character → vehicle.
- The ride is stepped by `CharacterVehicleUse.control` after the controller, so it overrides that frame's intent. The pose phases ease in the vehicle's frame (a moving vehicle carries the pose) and hand the character `use.set_ride_pose(point, facing, fold, step)`; `step` is the motion through the vehicle's frame, so the legs step with the pose, not the vehicle. The phases (`Phase`) are in `vehicle_boarding.gd`; V3 and V4 describe them.
- **Death** (`Character._die` → `abandon()`) frees the seat, leaves the door as it is and calls `use.end_ride()`. The character's collision shape is disabled with `set_deferred` at the first ride pose and enabled at `use.end_ride`; the exception covers the walk to the door before that.
- **After the ride** the vehicle goes to the character's `use.keep_clear_of(body)` (interface 19): the exception stays until the character's circle (+`CharacterUse.CLEAR_MARGIN`) no longer overlaps, so stepping out never shoves the vehicle. Boarding it again calls `use.stop_clearing(body)`.

## Contacts and harm (V6)

- **What is touched is found by a shape query**, never by Jolt's contact events (nondeterministic): `read` (in `_physics_process`, before the step) queries the vehicle's outline shape in the twin space with a margin, page by page (a floor slab or wall segment takes a hit too), the bodies nearest first, and takes each body's strongest contact with `get_rest_info`. **The closing speed comes from the step's start velocities** (`_last_velocity`, `_last_spin`, kept by `remember` after the drive's step). The other body's velocity is a `CharacterBody2D`'s own `velocity`, never its position delta; a free piece first met is taken to have lain at rest (the step that met it has carried it along).
- **The vehicle does not collide with a character in 3D** (its mask lacks `TWIN_CHARACTER`): it is never stopped dead by one. `_pile` finds, by 3D queries in the twin space, what stands in front (living characters and free pushable pieces, `pile_depth` members, the rest `blocked`), and `_strike_pile` meets vehicle and pile as two bodies: **blocked** (a wall behind: the wall stops the vehicle) posts `crash`; **free** applies the impulse `J` to the vehicle's velocity, shoves each character on and queues a blow per character not already in a pile for `rehit_time`. One run-in is one blow. A pile is struck only with a living character in it.
- **Furniture** is a free 3D body (`PieceBody`): the engine solves it against the vehicle (two dynamic bodies), and `_strike_piece` adds the bumper's blow on a piece first met above `crash_min_speed`: `strike_share` of the closing speed times its mass, through `Knockback.push` at `VehicleCollisionConfig.strike_height` (sill plus half the bumper), so a tall thin piece goes over and a low heavy one slides. The blow is added momentum (V6); only roll and pitch are locked.
- `apply()` runs in `_physics_process`, outside the flush where a death may change bodies. `process_physics_priority` −1 moves the vehicle before the characters, so a shoved character moves off in the same frame.
- **A corpse still blocks rigid bodies** (on no layer, but its mask collides), hence a collision exception once a struck character is dead.
- Anything but a character that is struck faster than `crash_min_speed` posts `crash` at once.

## Hittable (interface 3) and events (interface 10)

`get_surface()` is metal from the row. `take_hit` shoves, dents (`Deformable.record`) and throws debris; there is no destruction, and occupants are not hit through the body (they have no collision shape while riding).

Events: `&"vehicle"` (`stage`: `ignition`, `door_open`, `slide_open`, `door_close`, `slide_close`, `crash`, `bump_character`), `&"engine"` (`start` / `stop`: `drive.start_engine` / `stop_engine`), `&"skid"` (`drive.update_skid()`, hysteresis `skid_start_slip` / `skid_stop_slip`). Audio voices them and follows the loops by duck-typed `engine_state()`, `slip()` and `speed()` (`domain-audio`). The camera reads `use.vehicle().view_zoom_out()` duck-typed (`VehicleDriveConfig.zoom_out`).

## Gotchas

- **A body added this frame is not in the space yet** (the 2D footprint, nor its 3D body: the twin space builds that on the next update), so a shape query (`is_clear`, a probe's ray) on that frame misses it, and `linear_velocity` set on the footprint then is lost; `TestWorld` waits a physics frame after placing vehicles. A script that wakes the 3D body must call `VehicleBody.wake()` (the `sleeping = false` shim does), or the twin space never hears of it. `max_linear_velocity` 5000 px/s is above a vehicle's top speed (1280): no raise needed.
- **Arena size at these speeds:** a test running flat out for a second needs about 1000 px; a full-lock circle at walking pace is about 200 px.
- The `bounce` value is tiny on purpose: a crash near the top speed rebounds under 40 px/s, which rolling stops within a second (`vehicle/crash_into_wall_stops`).

**Interfaces:** 3 (hittable), 4 (`Deformable`, `Physics.impact_impulse` / `spawn_debris`), 5 (pushable), 7 (group `characters`; the controller fields a ride writes), 10 (EventBus), 11 (`PhysicsLayers.SOLID`), 12 (Art), 19 (Character ↔ Vehicle), 29 (`VehicleTwins`: the twin 3D space).
