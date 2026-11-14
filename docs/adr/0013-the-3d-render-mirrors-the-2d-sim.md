# The 3D render mirrors the 2D sim; it does not replace it

The isometric 3D render (issue #193) is a second way to draw the match, not a second simulation. The sim (physics, collision, navigation,
AI, bullets, grenades, the view cone) stays 2D and untouched; in the 3D render mode a **3D mirror** (`WorldMirror`, interface 27) follows
every drawn 2D body in a 3D world each frame, 2D `(x, y)` to 3D `(x, 0, y)` at the one scale `RenderConfig.unit`, and an orthographic camera
rig follows the sim's `Camera2D`. The 2D world is not drawn in that mode (hidden before the match is built, no 2D lights built), which is the
whole of the frame-time win the spike measured (2D 18.8 ms, 3D proxies 11.1 ms mean at 1152x648 in the 10v10 district); height is visual only.

## Considered options

- **Move the simulation to 3D.** Grenade arcs, real line-of-sight cover, storeys, a 3D ragdoll and 3D navigation, but it rewrites the physics,
  the AI's reasoning, the nav bake and every test that asserts on them, and the suite that pins today's behaviour would stop pinning anything.
  Out of scope of #193 and a ticket of its own; the mirror leaves that door open (a body that moves in 3D would only change what the mirror reads).
- **The mirror's own rule for what to follow.** A scene-side `Node3D` per object (each domain adds its mesh to its own scene) was rejected: it
  spreads the 2D-to-3D mapping over every factory and every body, so two scales and two orders could drift. One registry in Art holds the
  mapping, the update rule and the per-kind mesh hook; each domain supplies its mesh through the hook and never moves it.
- **The render mode as a second build of the world.** 3D mode builds the same bodies as 2D (so the sim is the same), and only what exists to
  be drawn is skipped where that is cheap and safe (the 2D lights; the world is hidden for the rest). Skipping every painter would change what
  a `Node2D` is and break the tests that read them, for a saving the hidden world already gives.

## Consequences

- The render mode is a saved setting applied at the next match. A running match keeps its mode; there is no live switch (the first 3D frames
  compile pipelines and re-showing the 2D world costs a one-off hitch).
- The mirror's update rule is a hot loop: write only when a body's 2D transform changed, skip a sleeping `RigidBody2D`, check a freed body untyped.
- The player's aim and keys stay world-relative until the camera-turn jobs give `Pointer` its 3D body; vision and debug overlays are drawn flat on
  the ground plane in later jobs. A 2D match is the game as it was, and the 2D render is deleted only at the end of #193.
