---
name: domain-vehicle
description: Use when editing scenes/vehicle/ or working on cars and vans: driving feel, getting in and out, doors and seats, collisions and harm, vehicle art.
---

# Vehicles domain

A drivable **car** and **van** (one scene each, inheriting `vehicle.tscn`). Only `sandboxes/vehicle_sandbox.gd` and the tests (`TestSetup.vehicle`) place them. Main, World-Gen and the match never do, the nav map does not carve them, and the AI sees a parked one only as a solid body. The spec, rule by rule with its tests, is `docs/vehicles.md` (V1 to V9, with the numbers). Tests: `tests/vehicle/`, probed through `tests/_vehicle/` (`vehicle_probe.gd`, `vehicle_frame_probe.gd`, `vehicle_ride_probe.gd`; `domain-testing`) plus `tests/audio/vehicle_*`, `tests/general/camera_zooms_out_driving_test.gd`, `tests/general/use_vehicle_key_test.gd`.

```
player_controller (E) ─▶ Character.use.try_use_vehicle ─▶ CharacterVehicleUse ─▶ vehicle.board(character, door) ─▶ VehicleBoarding (the ride)
VehicleBoarding ──(movement.move_input / aim_point, use.set_ride_pose, use.end_ride)──▶ Character;  seated driver: move_input / run_input ─▶ vehicle.drive_input
vehicle._integrate_forces ─▶ drive.step (VehicleDrive)   /   _contacts (VehicleContacts) ─▶ crash events, characters struck
```

## Files

| File | Role |
|---|---|
| `vehicle.gd` | Root `RigidBody2D` (no `class_name`; group `vehicles`): body set-up, the drivable contract (interface 19), the hittable contract, its parts (`cabin`, `drive`, `_contacts`) and `post`, through which every `vehicle` event goes. |
| `vehicle_cabin.gd` (`VehicleCabin`) | Doors, seats and whose ride is whose (`take_seat` starts a ride, `release` ends it). |
| `vehicle_drive.gd` | The bicycle model, stepped in `_integrate_forces`; the drive `intent`, engine, skids. `tyre_solve.gd` (`TyreSolve`) is one step's sideways solve. |
| `vehicle_contacts.gd` (`VehicleContacts`) | Contacts and harm (V6): `read`/`remember` around the drive's step, `apply` in `_physics_process`. |
| `vehicle_door.gd` | One door in the vehicle's frame: eased open amount, pose, stand and entry points, `is_clear`. |
| `vehicle_boarding.gd` | One character's ride: a timed phase machine (`Phase`, inner `Pose`) from E beside the vehicle to the last step out. |
| `character_vehicle_use.gd` | The character's component (built by `CharacterUse.attach`): picks the door, steps the ride after the controller, abandons it on death. |
| `vehicle_visuals.gd`, `art/` | Draw: read `art.md` before touching the painters or the chassis and roof layers. |
| `vehicle_config.gd` (`VehicleConfig`) | `kinds` row per kind (`car`, `van`: size, mass, engine, axles, grips, `seats`, `doors`) and `looks` row per kind (the painters' proportions). Shared numbers: `VehicleBoardingConfig`, `VehicleDoorConfig`, `VehicleDriveConfig`, `VehicleCollisionConfig`, `VehicleArtConfig`. |

**Frames.** Rotation 0 = nose toward +x; the vehicle's own frame has x forward, y to its right. Every door, seat, axle and `looks` entry is in that frame. Art is painted in Art's canonical frame (front toward +y) and drawn turned by `BODY_TURN`.

## Body and driving (V5)

- The collider is one convex polygon of `outline()`; the `Deformable` child records dents but nothing rebuilds the collider from them. `can_sleep` is off while the engine runs.
- `_integrate_forces` reads the contacts first, then `drive.step` writes the velocities for the next step from the `intent` (`throttle`, `steer`, `handbrake`, `brake`: from `drive_input`, driver only and engine running, or `drive.brake_input`, which holds to a stop and never reverses).
- **Steering lock is derived, not tuned.** Slow, full lock is `steer_angle`; at speed it is the angle that asks the front axle for exactly the sideways grip it holds (`lock(row, speed)`), so full lock never plows or spins. `steer_share` eases at `steer_rate / steer_angle` per second, so full lock takes the same time at any speed.
- **Throttle tapers to the top speed.** `_engine` falls with the cube of the speed share to exactly rolling + drag at `top_speed`, so full throttle settles there whatever the drag.
- **Balance.** The rear limit is kept above the front's, so at the limit the front slides first (understeer). A weaker rear would spin on a fast turn. The handbrake leaves the rear `handbrake_grip` of its grip: it must stay a few px/s², as locked tyres still hold sideways; more damps the tail's swing and `vehicle/handbrake_slides_rear` fails.
- Under `stop_speed` with no push the velocities are zeroed (static grip).

## Doors, seats and the ride (V1 to V4)

- Door kinds: `swing`, `slide`, `rear` (swings out behind). The van's side and rear-right doors share the seat `cargo_right`: taking one makes the other's seat taken.
- The open amount is linear in time and read eased (`amount()`), a close gathering speed into the slam. `update(delta)` returns true on the frame a closing door shuts, and the vehicle posts the close then.
- `is_clear(vehicle, exclude, radius)` queries the swept sector (or the slide track), then the user's circle at the stand point. A wall, furniture, a character or another vehicle blocks it.
- **Picking the door** (`CharacterVehicleUse.try_use_vehicle`): seated → `vehicle.exit`; on foot → the doors of every vehicle in the group `vehicles` within `door_reach` and moving slower than `board_max_speed`, nearest first; the first whose `board(character, door)` returns a ride wins. `board` refuses at speed, a taken seat, a character already riding or a blocked door, and adds a collision exception character → vehicle.
- The ride is stepped by `CharacterVehicleUse.control` after the controller, so it overrides that frame's intent. The pose phases ease in the vehicle's frame (a moving vehicle carries the pose) and hand the character `use.set_ride_pose(point, facing, fold, step)`; `step` is the motion through the vehicle's frame, so the legs step with the pose, not the vehicle. The phases (`Phase`) are in `vehicle_boarding.gd`; V3 and V4 describe them.
- **Death** (`Character._die` → `abandon()`) frees the seat, leaves the door as it is and calls `use.end_ride()`. The character's collision shape is disabled with `set_deferred` at the first ride pose and enabled at `use.end_ride`; the exception covers the walk to the door before that.
- **After the ride** the vehicle goes to the character's `use.keep_clear_of(body)` (interface 19): the exception stays until the character's circle (+`CharacterUse.CLEAR_MARGIN`) no longer overlaps, so stepping out never shoves the vehicle. Boarding it again calls `use.stop_clearing(body)`.

## Contacts and harm (V6)

- **The closing speed comes from the step's start velocities** (`_last_velocity`, `_last_spin`, kept by `remember` after the drive's step): the solver has already stopped the vehicle by the time `_integrate_forces` sees the contact. The other body's velocity is a `CharacterBody2D`'s own `velocity`, never its position delta: pressed against the vehicle, its `move_and_slide` barely moves it for a frame however hard its knockback, which would read a stopped body.
- **Characters are immovable to the solver**, so it stops the vehicle on one (and on a chair pressed against one) as on a wall. `_pile` finds what stands in front (living characters and free pushable pieces, `pile_depth` members, the rest `blocked`), and `_strike_pile` meets vehicle and pile as two bodies: **blocked** (a wall behind) keeps the solver's stop and posts `crash`; **free** applies the impulse `J`, shoves each member on and queues a blow per character not already in a pile for `rehit_time`. One run-in is one blow. Furniture pressing furniture stays the solver's.
- `apply()` runs in `_physics_process`, outside the flush where a death may change bodies. `process_physics_priority` −1 moves the vehicle before the characters, so a shoved character moves off in the same frame.
- **A corpse still blocks rigid bodies** (on no layer, but its mask collides), hence a collision exception once a struck character is dead.
- Anything but a character that is struck faster than `crash_min_speed` posts `crash` at once.

## Hittable (interface 3) and events (interface 10)

`get_surface()` is metal from the row. `take_hit` shoves, dents (`Deformable.record`) and throws debris; there is no destruction, and occupants are not hit through the body (they have no collision shape while riding).

Events: `&"vehicle"` (`stage`: `ignition`, `door_open`, `slide_open`, `door_close`, `slide_close`, `crash`, `bump_character`), `&"engine"` (`start` / `stop`: `drive.start_engine` / `stop_engine`), `&"skid"` (`drive.update_skid()`, hysteresis `skid_start_slip` / `skid_stop_slip`). Audio voices them and follows the loops by duck-typed `engine_state()`, `slip()` and `speed()` (`domain-audio`). The camera reads `use.vehicle().view_zoom_out()` duck-typed (`VehicleDriveConfig.zoom_out`).

## Gotchas

- **A `RigidBody2D` added this frame is not in the space yet**, so a shape query (`is_clear`, a probe's ray) on that frame misses it; `TestWorld` waits a physics frame after placing vehicles.
- **Arena size at these speeds:** a test running flat out for a second needs about 1000 px; a full-lock circle at walking pace is about 200 px.
- The `bounce` value is tiny on purpose: a crash near the top speed rebounds under 40 px/s, which rolling stops within a second (`vehicle/crash_into_wall_stops`).

**Interfaces:** 3 (hittable), 4 (`Deformable`, `Physics.impact_impulse` / `spawn_debris`), 5 (pushable), 7 (group `characters`; the controller fields a ride writes), 10 (EventBus), 11 (`PhysicsLayers.SOLID`, `DrawLayers`), 12 (Art), 19 (Character ↔ Vehicle).
