19. **Character ↔ Vehicle: the drivable contract** (`scenes/vehicle/`; spec `docs/vehicles.md`)
    - **The character's side.** `character.use` (`character/character_use.gd`, `CharacterUse`) composes the Vehicles domain's
      `CharacterVehicleUse` (`vehicle/character_vehicle_use.gd`) and forwards opaque calls: `use.try_use()` (E; refused while dead or
      in an object interaction: board by the door whose handle is nearest, or get out; a standing house door in reach and nearer works that door
      instead, interface 24), `nearest_door_distance() -> float` (on `CharacterVehicleUse`: how far the nearest handle a character on foot could board
      by is, `INF` with none or riding; `use.use_target()` weighs it against a house door), `use.vehicle() -> Node` (the vehicle it is boarding,
      riding in or leaving; null on foot) and `use.is_in_vehicle()` (test read: seated only). The character steps the component once a
      physics frame right after its controller (`control(delta)`), so a ride overrides that frame's intent, and calls `abandon()` from `_die`
      (the ride ends where the body is). While a ride lasts (`is_active()`: from the E press to the last step out) `use.is_busy()` is true
      and `use.try_interact()` / `use.interact_with` are refused.
    - **What the Vehicles domain calls on the character.** On the walk to the door its controller fields `movement.move_input` /
      `movement.aim_point` / `movement.run_input` (7); from the driver's seat it reads `movement.move_input` / `movement.run_input` as the
      drive intent. The ride API: `use.set_ride_pose(at, toward, fold, step := Vector2.ZERO)` (world point, facing, fold 0 standing .. 1
      seated, `step` the legs' motion through the vehicle's frame in px/s so a carried body does not walk at the vehicle's speed). The first
      pose cancels a reload, puts the held item away (`inventory.current_item()` null) and disables the collision shape; the fold is the
      drawn crouch fold (`movement.posture_folded()` reads it). `use.end_ride()` puts it back on its own feet. It also reads `facing`,
      `radius`, `movement.speed`, `global_position`; for a character it strikes (a body in the group `characters`, 7) it reads `is_dead`,
      `health`, `velocity`, `get_mass()` and calls `apply_impulse` / `take_damage(amount)`. After a ride the vehicle goes to
      `use.keep_clear_of(body)` (as in 8: the collision exception is dropped once the body is clear); boarding the vehicle just left calls
      `use.stop_clearing(body)`.
    - **The vehicle** (`vehicle.gd`, a `RigidBody2D` on `PhysicsLayers.SOLID`, group `vehicles`): `doors() -> Array` (`[{ id, kind`
      (`swing` / `slide` / `rear`)`, seat, handle, open` (0..1)`, hinge, angle, offset }]`, world space), `seats() -> Array`
      (`[{ id, occupant }]`), `driver() -> Node`, `board(character, door_id) -> RefCounted` (the ride, or null when that door cannot be used
      now), `exit(character) -> bool`, `drive_input(character, throttle, steer, handbrake)` (driver only, engine running), and the reads
      `speed()` (px/s, unsigned), `engine_state()` (`{ running, rpm, load }`), `slip()` (0 while the tyres grip), `wheel_angle()`,
      `brake_lights()`, `view_zoom_out()` (`VehicleDriveConfig.zoom_out` × speed / top speed: how far a camera following someone aboard zooms
      out). Two draw layers are contract too (tests find them by name): child `Chassis` (`layer` `"chassis"`, at `DrawLayers.UNDER_VEHICLE`)
      and child `Roof` (`layer` `"roof"`, at `DrawLayers.ABOVE`).
    - **Its other contracts:** hittable (3), Deformable / debris / impulse (4), pushable (5), the `vehicle` / `engine` / `skid` topics (10),
      its painters (12). General's camera reads `target.use.vehicle().view_zoom_out()` duck-typed (`has_method`), never
      `VehicleDriveConfig`; `player_controller.gd` calls `use.try_use()` on `Keybinds.USE` (E). Only the sandbox and the
      tests place a vehicle: Main, World-Gen, the nav map and the AI do not know them.
