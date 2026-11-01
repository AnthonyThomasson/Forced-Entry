# Doors are driven bodies, left out of the nav bake

A door (issue #21, `docs/doors.md`) turns about a hinge between shut and 90°, stops bodies when it is shut, is shot
through, kicked in and knocked down, and every character, round, ray of sight and light has to treat it as the thing it
is at the angle it stands at. Two choices shape it, and a reader who meets the code will ask both.

## Driven by code, not a physics hinge

The leaf is an `AnimatableBody2D` the code turns (`Door._physics_process` sets its transform each step to the eased
angle), not a `RigidBody2D` on a `PinJoint2D` or a `DampedSpringJoint2D` the engine swings.

- **A swing is a script, not a simulation.** The player wants a door that opens in 0.4 s, opens to a scroll notch's 20° and
  stays there; the AI wants one it can open fully and rely on; a burst latch throws it open at a fixed rate. A hinge
  joint under a character leaning on it, a shove or a stray round would swing, jitter, sag and settle on its own.
  A driven body is exactly where the code puts it.
- **The pushable and hittable contracts stay cheap.** A rigid body answers `apply_impulse` by moving; a shut door answers
  it by not moving (an ajar one turns about its hinge), and a melee strike names its kind to the door through `take_blow`. The latch, the burst and the fall are the door's rules, written once.
- **A kinematic body pushes.** Godot moves an `AnimatableBody2D` through the physics server, so what it sweeps over is
  depenetrated; but a leaf that must stop at furniture, nudge a character and refuse to squash one against a wall needs the
  rule in code (`Door._blocked`, `_nudged`), asked of the space before the leaf turns there.
- **Cost.** One body per door, a few dozen in a house, none simulated: no joint solver, no sleeping, no tuning of damping.

The leaf is the only collider of a door and is solid at every height (`coverage` 100); a knocked-down door drops
its collider (layer 0) and lies flat as a slab.

## Left out of the nav bakes

A baked static collider is a wall to the navigation mesh. A shut door is in the doorway it stands in, and an
`AnimatableBody2D` is a `StaticBody2D` to the engine's parse, so a naive bake would seal every shut door's doorway and
the AI could never plan through one: the room behind it would be unreachable, and the walker that must open it could not
even route to it. So `NavBuilder` leaves every door out of every bake: the planning map, the steering map and the avoid
maps (they share the one parse, `_walls_of`). Paths go through the doorway as if it were open; the walker stops at the
leaf if it is in the way and works it (`docs/doors.md` DR14).

How: the parse is made with the bodies of the group `doors` under the house taken off the solid layer for its length. The
group is the only link: Navigation stays a leaf that imports nothing of Objects, as before. Alternatives considered:
- *Parenting the doors outside the house's subtree*: the parse then never sees them, but doors would depend on the
  caller's tree, and the Lighting, per-floor and cleanup code all walk the house's descendants.
- *A `RigidBody2D` door*: the nav parse ignores rigid bodies (furniture is carved from its footprints instead), but then the
  leaf is a physics-simulated body again (the first choice), and a rigid-body door would be carved as a hole by the furniture rule.
- *Subtracting the doors' outlines from the parsed obstructions afterwards*: the outlines come out unlabelled and merged
  with the walls' at the jambs, so the subtraction would cut the jambs too.

`tests/navigation/door_not_baked_test.gd` pins it (both maps path through a shut door's doorway); take the exclusion out and it goes red.
