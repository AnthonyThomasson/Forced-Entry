19. **Character ↔ Vehicle: the drivable contract** (`scenes/vehicle/`; spec `docs/vehicles.md`)
    - **The character's side.** `character.use` (`character/character_use.gd`, `CharacterUse`) composes the Vehicles domain's
      `CharacterVehicleUse` (`vehicle/character_vehicle_use.gd`) and forwards opaque calls: `use.try_interact()` (Space; refused while dead; seated it gets out, on foot it boards by
      the door whose handle is nearest when a vehicle's door is the thing nearest the mouse, else it works the chair or standing house door that is,
      interfaces 8, 24), `nearest_door_distance(point) -> float` (on `CharacterVehicleUse`: how far the outline of the nearest vehicle with a door a character
      on foot could board by is, `INF` with none or riding; `use.interact_target()` weighs it against a chair and a house door), `use.vehicle() -> Node` (the vehicle it is boarding,
      riding in or leaving; null on foot) and `use.is_in_vehicle()` (test read: seated only). The character steps the component once a
      physics frame right after its controller (`control(delta)`), so a ride overrides that frame's intent, and calls `abandon()` from `_die`
      (the ride ends where the body is). While a ride lasts (`is_active()`: from the Space press to the last step out) `use.is_busy()` is true
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
    - **The vehicle** (`vehicle.gd`, the plan handle, a plain `Node2D` in the groups `vehicles` and `TwinSpace.BODIES` / `HARD`, of a free 3D body locked upright, `VehicleBody`, which leads it: driving, collisions and mass are the 3D body's; `linear_velocity`, `angular_velocity`, `mass`, `sleeping`, `apply_impulse` and `get_mass()` on the footprint answer through it): `doors() -> Array` (`[{ id, kind`
      (`swing` / `slide` / `rear`)`, seat, handle, open` (0..1)`, hinge, angle, offset }]`, world space), `seats() -> Array`
      (`[{ id, occupant }]`), `driver() -> Node`, `can_board(character, door_id) -> bool` (the checks of `board`, changing nothing) and `board(character, door_id) -> RefCounted` (the ride, or null when that door cannot be used
      now), `exit(character) -> bool`, `drive_input(character, throttle, steer, handbrake)` (driver only, engine running), and the reads
      `speed()` (px/s, unsigned), `engine_state()` (`{ running, rpm, load }`), `slip()` (0 while the tyres grip), `wheel_angle()`,
      `brake_lights()`, `view_zoom_out()` (`VehicleDriveConfig.zoom_out` × speed / top speed: how far a camera following someone aboard zooms
      out).
    - **Its other contracts:** hittable (3), Deformable / debris / impulse (4), pushable (5), the `vehicle` / `engine` / `skid` topics (10),
      its painters (12). General's camera reads `target.use.vehicle().view_zoom_out()` duck-typed (`has_method`), never
      `VehicleDriveConfig`; `player_controller.gd` calls `use.try_interact()` on `Keybinds.INTERACT` (Space). Only the sandbox and the
      tests place a vehicle: Main, World-Gen, the nav map and the AI do not know them.
