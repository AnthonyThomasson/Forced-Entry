5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v, at = Vector2.ZERO)` + `get_mass()`; `at` is the contact offset from
   the piece's origin (world orientation; omitted = a central shove).
   - Furniture is a `RigidBody2D`: its native methods serve the contract, and an off-centre shove turns it. The character ignores `at`
     and integrates knockback into locomotion. Once the twin space has taken a free piece over (interface 29), the piece is led by a
     free 3D body (`PieceBody`) and its `RigidBody2D` is a frozen footprint that a native `apply_impulse` moves nothing of, so **a
     pusher goes through `Knockback.push(body, impulse, at = Vector2.ZERO, height = -1.0)`**: `height` is px above the floor (-1: the
     body's centre), the real point of the blow (a bullet's `HitInfo.height`, a blast's burst height, a fist's, a foot's, the hip of a
     walking push: `BodyHeights.contact(part, posture)`), so a tall thin piece struck high tips and a low heavy one slides. A pusher that is carrying a piece along (a walking
     push, a leg press: `CharacterPush.shove(piece, dir, impulse, contact: Vector3, speed)`, `contact.z` the height) is clamped to the
     piece's centre height, so it slides it and never flips it; a blow is not. `Knockback.push` falls back to `apply_impulse(v, at)`
     for any other pushable.
   - A character is a 3D leader too (interface 29, `CharacterTwin`): its walk pushes what the 3D body slid into at hip height, and its
     punch, kick, shoves and leg press are cast and struck in the twin space at their real heights (`BodyHeights.contact`: hip, fist,
     knee, leg, ankle; a kick lands at the shin, a punch from the ankle up to the fist), so a blow at a free piece reaches
     its `PieceBody` through `Knockback.push` at the point and height struck: a fist high on a tall thin piece tips it, a foot low on it slides it.
   - Pushers: furniture→character contact transfers, bullet impacts, an explosion's blast (central), the character's punch, kick, leg press
     and walking push (each at its contact point).
   - A vehicle (`vehicle.gd`, a `RigidBody2D`) is pushable through its native methods (a bullet shoves it at the hit). It shoves free furniture
     through the physics solver, and a piece led by a 3D body (to the 2D solver as immovable as a character) as a pile through
     `Knockback.push` (`VehicleContacts`), a character it strikes through the character's `apply_impulse` (interface 19), and a piece pressed against
     a character through the piece's `apply_impulse`, read against its `linear_velocity`.
   - To carry a piece at walking pace instead of launching it, a pusher may read a `RigidBody2D` pushable's `linear_velocity` /
     `angular_velocity` and its inverse inertia (`PhysicsServer2D.body_get_direct_state`) and cap its shove by them; a pushable without
     them (a character) is shoved uncapped.
   - A world `Door` (interface 24) is a driven body: a shut door is never moved by a shove; an ajar or open one is turned about its hinge
     away from the shover (`docs/doors.md` DR10), so no pusher caps it. A walking push and a punch never count against a latch.
