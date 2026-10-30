19. **Character ↔ Vehicle: the drivable contract** (`scenes/vehicle/`; spec `docs/vehicles.md`)
    - **The character's side.** `character.gd` composes the Vehicles domain's `CharacterVehicleUse` (`vehicle/character_vehicle_use.gd`,
      preloaded and added in `_ready` like `CharacterInteraction`) and forwards opaque calls: `use.try_use_vehicle()` (E, refused while dead or
      in an object interaction: board by the door whose handle is nearest, or get out), `use.vehicle() -> Node` (the vehicle it is boarding, riding
      in or getting out of; null on foot) and `use.is_in_vehicle()` (seated only). It steps the component once a physics frame right after its
      controller (`control(delta)`), so a ride overrides that frame's intent, and calls `abandon()` from `_die` (the ride ends where the body is).
      It asks the component `is_active()` (true from the E press to the last step out): while a ride lasts `use.is_busy()` is true and
      `use.try_interact()` / `use.interact_with` are refused.
    - **What the Vehicles domain calls on the character.** During the walk to the door its controller fields `movement.move_input` / `movement.aim_point` /
      `movement.run_input` (interface 7), and from the driver's seat it reads `movement.move_input` / `movement.run_input` as the drive intent; then the ride API:
      `use.set_ride_pose(at, toward, fold, step := Vector2.ZERO)` (world point, facing, fold 0 standing .. 1 seated, and `step`, the legs' motion
      through the vehicle's frame in px/s, so a carried body does not walk at the vehicle's speed): the first pose cancels a reload, puts the
      held item away (`inventory.current_item()` null) and disables the collision shape; the fold is the drawn crouch fold (`movement.posture_folded()` reads it);
      and `use.end_ride()` (on its own feet again, shape on, item back). It also reads `facing`, `radius`, `movement.speed`, `global_position`, and for a
      character it strikes (a body in the group `characters`, interface 7) `is_dead`, `health`, `velocity`, `get_mass()` and calls
      `apply_impulse` / `take_damage(amount)`; collision exceptions are Godot's own (`add_collision_exception_with` / `remove_...`); after a
      ride the vehicle goes to the character's `use.keep_clear_of(body)` (as in interface 8: the exception is dropped once the body is clear of it),
      and boarding the vehicle just left calls `use.stop_clearing(body)`.
    - **The vehicle** (`vehicle.gd`, a `RigidBody2D` on `PhysicsLayers.SOLID`, found by the group `vehicles`): `doors() -> Array`
      (`[{ id, kind` (`swing` / `slide` / `rear`)`, seat, handle, open` (0..1)`, hinge, angle, offset }]`, world space), `seats() -> Array`
      (`[{ id, occupant }]`), `driver() -> Node`, `board(character, door_id) -> RefCounted` (the ride, or null when that door cannot be used
      now), `exit(character) -> bool`, `drive_input(character, throttle, steer, handbrake)` (driver only, engine running), and the reads
      `speed()` (px/s, unsigned), `engine_state()` (`{ running, rpm, load }`), `slip()` (0 while the tyres grip), `wheel_angle()`,
      `brake_lights()` and `view_zoom_out()` (`VehicleDriveConfig.zoom_out` × speed / top speed: how far a camera following someone
      aboard zooms out). Its two draw layers are part of the contract too (the tests find them by name): the child `Chassis` (`layer`
      export `"chassis"`, at `DrawLayers.UNDER_VEHICLE`) and the child `Roof` (`layer` `"roof"`, at `DrawLayers.ABOVE`). Everything else on it is Vehicles-internal, for its ride and visuals:
      - `half_size`, `outline`, `row`, `hit_marks` and `post` (a `vehicle` event);
      - its `cabin` (`VehicleCabin`, `vehicle/vehicle_cabin.gd`: the doors and seats, `door_list`, `door`, `seat_point`,
        `occupant`, `is_free`, `reserve`, `change_seat`, `release`, `open_door` / `close_door`, `exit_door`, and the rides);
      - its `drive` (the driving model, `vehicle_drive.gd`, with the intent and the engine: `start_engine` / `stop_engine`,
        `brake_input`);
      - its contacts (`VehicleContacts`, `vehicle/vehicle_contacts.gd`, V6).
    - **Its other contracts:** hittable (3), Deformable / debris / impulse (4), pushable (5), the `vehicle` / `engine` / `skid` topics (10)
      and its painters (12). General's camera reads `target.use.vehicle().view_zoom_out()` duck-typed (`has_method`), never `VehicleDriveConfig`;
      `player_controller.gd` calls `use.try_use_vehicle()` on `Keybinds.USE_VEHICLE` (E). Only the sandbox and the tests place a vehicle:
      Main, World-Gen, the nav map and the AI do not know them.
