# The view draws the twins' world; each body carries its mesh

Supersedes [ADR 0013](0013-the-3d-render-mirrors-the-2d-sim.md). The 3D view (#193) was a **mirror**: a registry (`WorldMirror`) that followed every
drawn 2D body in a `Node3D` world of its own, a proxy box per collision shape until a domain's mesh replaced it, written each frame the body moved. #194 put a 3D
twin of every solid body into the sim's own 3D space (`TwinSpace`, interface 29, [ADR 0014](0014-twin-staging-and-plan-space.md)), so the mirror had become a
second copy of what the twins already hold: a pose written twice, a world of the view's own beside the twins' world, and a 2D shape read only to size a stand-in box.

**Decision.** The view draws the twin space's `World3D` (`View3D.mirror_world` swaps the viewport's world for it). Each body **carries its mesh on its twin**: Art's `MeshCarrier`
(interface 27) is fed by `TwinSpace.twinned` and `retwinned`, builds the mesh the body's domain registered (`builders`, unchanged: a kind or a finer key) and hangs it on the
twin as a child with no transform of its own, so the picture is where the twin is and nothing writes it (a character's mesh holds its 2D turn, the round twin never turns).
The shown rules (the body's `visible`, a seated character's disabled shapes, the player's view: `MirrorSight`), `mirror_update`, `remirror`, `on_body_died`, `follows_shapes`
and the `built` signal a wall fade listens to are the mirror's, kept. What is drawn but is no body (floor stencils, lying items) is shown by a small `MeshFollower` that keeps the
mirror's `track` / `track_group`; the effects' and shots' layers hang in the view's viewport. `WorldMirror`, `MirrorConfig` and the proxy are deleted.

**Fallbacks, decided.** A body no builder gives a mesh has **none**, not a box: a stand-in would be sized from a 2D collision shape, which the 2D-space deletion (del2d-c)
removes, and every kind that ships has a builder, so nothing drawn goes missing. A body the space gave no twin (a non-solid piece: a rug, a mat, which never moves) has its
mesh placed where it stands, once, a child of the carrier (`TwinSpace.untwinned`), never followed.

**Consequences.** One pose, not two; no second world to keep in step; a mesh is where its twin is, and a 2D handle is written from that pose in the same physics frame, so a render frame finds them one (a read that awaits `physics_frame` sees a car's handle a step behind its mesh: 8 px at 500 px/s). Two carriers on one twin space would mesh each body twice (one view per world). A test that wants a body the
domains twin not (a hand-made probe) gives the space a plain `Node3D` twin (`tests/_art/art_probe_twins.gd`). The picture is unchanged pixel for pixel (the carried picture tests compare it to
the same meshes placed by hand, `tests/_art/art_followed_baseline.gd`), and the carrier's update was measured once against the mirror's carried arm and came out under it (0.29 ms against 0.38 to 0.40 ms; the yard 2.05 to 2.1 ms against 2.1 to 2.4 ms). What the tests assert (`perf/mesh_carrier_cost`, `mesh_carrier_fleet_cost`, `mesh_follower_cost`) is a ratio to a fixed reference loop timed in the same frames, at about 4x the ratio measured, which a loaded machine does not move; the A/B itself is not kept.
