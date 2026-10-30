5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v, at = Vector2.ZERO)` + `get_mass()`,
   `at` the contact offset from the piece's origin (in world orientation; omitted = a central shove).
   Furniture is a `RigidBody2D`, so its native methods (this is their signature) serve the contract and a shove off
   the centre turns it; the character ignores `at` and integrates knockback into locomotion. Used by
   furniture→character contact transfers, bullet impacts, an explosion's blast (central), and the character's punch,
   kick, leg press and walking push (each at its contact point). A vehicle (`vehicle.gd`, a `RigidBody2D`) is pushable through
   its native methods too (a bullet shoves it at the hit); it shoves furniture through the physics solver and a character it
   strikes through the character's `apply_impulse` (interface 19), and a piece pressed against a character it strikes (or
   that it presses against one) through the piece's `apply_impulse`, read against its `linear_velocity`. To carry a piece at walking pace instead of launching it,
   a pusher may also read a `RigidBody2D` pushable's `linear_velocity` / `angular_velocity` and the inverse inertia the
   physics server holds for it (`PhysicsServer2D.body_get_direct_state`), and cap its shove by them; a pushable without
   them (a character) is shoved uncapped.
