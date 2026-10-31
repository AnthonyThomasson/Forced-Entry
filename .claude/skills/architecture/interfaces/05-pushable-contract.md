5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v, at = Vector2.ZERO)` + `get_mass()`; `at` is the contact offset from
   the piece's origin (world orientation; omitted = a central shove).
   - Furniture is a `RigidBody2D`: its native methods serve the contract, and an off-centre shove turns it. The character ignores `at`
     and integrates knockback into locomotion.
   - Pushers: furniture→character contact transfers, bullet impacts, an explosion's blast (central), the character's punch, kick, leg press
     and walking push (each at its contact point).
   - A vehicle (`vehicle.gd`, a `RigidBody2D`) is pushable through its native methods (a bullet shoves it at the hit). It shoves furniture
     through the physics solver, a character it strikes through the character's `apply_impulse` (interface 19), and a piece pressed against
     a character through the piece's `apply_impulse`, read against its `linear_velocity`.
   - To carry a piece at walking pace instead of launching it, a pusher may read a `RigidBody2D` pushable's `linear_velocity` /
     `angular_velocity` and its inverse inertia (`PhysicsServer2D.body_get_direct_state`) and cap its shove by them; a pushable without
     them (a character) is shoved uncapped.
