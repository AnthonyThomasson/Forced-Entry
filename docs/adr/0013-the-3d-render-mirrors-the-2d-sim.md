# The 3D render mirrors the 2D sim; it does not replace it

The isometric 3D render (issue #193) is a second way to draw the match, not a second simulation. The sim (physics, collision, navigation,
AI, bullets, grenades, the view cone) stays 2D and untouched; in the 3D render mode a **3D mirror** (`WorldMirror`, interface 27) follows
every drawn 2D body in a 3D world each frame, 2D `(x, y)` to 3D `(x, 0, y)` at the one scale `RenderConfig.unit`, and an orthographic camera
rig follows the sim's `Camera2D`. The 2D world is not drawn in that mode (hidden before the match is built) and its 2D lights are not built;
the painters' textures and `LightOccluder2D`s still are until phase 3 deletes the 2D render. The vision memory's capture `SubViewport`, which would photograph
the hidden 2D world every frame, is not built in 3D: the player's view there is two masks (the cone now and where it was ever seen) that the toon shaders read by ground position, so walls, furniture and characters are shaded by the view and the memory is the current static world dimmed and greyed (`docs/player-vision.md` V12). The spike measured its win (2D 18.8 ms, 3D proxies 11.1 ms mean at 1152x648 in the 10v10
district) with none of that 2D work, so the rest of it is carried to those jobs; height is visual only.

**The meshes (phase 2).** Each domain owns the mesh of what it owns, as it owns its painters; Art gives them one kit (`MeshKit`, `MeshCache`, `MeshNodes`: low-poly
solids built in code in the art's px, converted by `RenderConfig.unit` in one place, one colour per face, one `Mesh` per distinct input) and the mirror one hook:
`builders[key]`, a kind or a finer key for one art id, `track` and `track_group` for what is drawn but no physics body. A domain registers its builders and Main plugs them into the
mirror, so Art imports none of them and a body with no builder is still its proxy. The toon material also carries phase 3's vision mask as global shader uniforms (default: everything
visible), so the mask needs no per-mesh edit. The design did not shift: the mirror's mapping, update rule and fallback are as above.

## Considered options

- **Move the simulation to 3D.** Grenade arcs, real line-of-sight cover, storeys, a 3D ragdoll and 3D navigation, but it rewrites the physics,
  the AI's reasoning, the nav bake and every test that asserts on them, and the suite that pins today's behaviour would stop pinning anything.
  Out of scope of #193 and a ticket of its own; the mirror leaves that door open (a body that moves in 3D would only change what the mirror reads).
- **The mirror's own rule for what to follow.** A scene-side `Node3D` per object (each domain adds its mesh to its own scene) was rejected: it
  spreads the 2D-to-3D mapping over every factory and every body, so two scales and two orders could drift. One registry in Art holds the
  mapping, the update rule and the per-kind mesh hook; each domain supplies its mesh through the hook and never moves it.
- **The render mode as a second build of the world.** 3D mode builds the same bodies as 2D (so the sim is the same), and of what exists only
  to be drawn it skips the 2D lights (the dusk's `CanvasModulate`, the `PointLight2D`s and the `WorldLighting` node: nothing but the 2D render
  reads them) and does not draw the world, which is hidden. The painters' textures and the `LightOccluder2D`s are still built: skipping them
  would change what a `Node2D` is and break the tests that read them, so they go when phase 3 deletes the 2D render, and the vision capture
  stops with the pixel-post job.

## Consequences

- The render mode is a saved setting applied at the next match. A running match keeps its mode; there is no live switch (the first 3D frames
  compile pipelines and re-showing the 2D world costs a one-off hitch).
- The mirror's update rule is a hot loop: write only when a body's 2D transform changed, skip a sleeping `RigidBody2D`, check a freed body untyped.
- The picture is drawn at a low internal resolution and upscaled with nearest filtering through a toon material and an outline pass (the pixel post, Art).
- `Pointer` has a 3D body (a screen point is the camera ray meeting the ground, through the displayed rect of the 3D view), WASD and the spectator's pan are
  screen-relative in 3D (a seated driver's keys stay raw) and Q / E turn the camera freely. The vision and debug overlays draw flat on the ground plane over
  the 3D view: each is moved under a `CanvasLayer` (`GroundLayer`: one shared by all the debug overlays) that follows the camera's ground-to-screen affine, because a hidden `CanvasItem` draws nothing.
  A 2D match is the game as it was, and the 2D render is deleted only at the end of #193.

## Addendum: the 2D render is deleted (#193 phase 3)

The rework gate was accepted and the user chose to delete the 2D render engine, so the 3D render is the game's only render and the "second way to draw the match" above is the only way. What went and why:

- **The render mode.** `Settings.render_mode`, `RENDER_2D` / `RENDER_3D`, its settings-page drop-down and a match spec's `render` are gone (a `render_mode` in an older settings file is skipped on load and not written back). Main always builds the 3D view and hides the `World`; every test world is shown by the same view when it is looked at (the in-game runner, `--shots`), and `Pointer` and the camera keep their canvas-transform body for a world with no 3D rig (a headless test world has no picture to convert for).
- **The 2D drawing.** Two renders meant two of everything: the 3D view's cost was the 2D world still built, painted (lit textures) and processed unseen, the vision capture and memory viewports among it. The player's view is two masks (`ViewGround`), the lights are `WorldLighting3D`, the debug overlays are the flat 2D drawing code on the ground layer (they stay, as planned). The domains' 2D visuals go with their jobs; what stays is the **sim** (2D physics, mirrored by `WorldMirror`), the `Camera2D` (Sound, the cull and the tests read it) and the **painters**, which are the one source of the textures (`PixelArt.render_flat`).
- **Why it was safe to do late.** The phase-1 spike's saving came from not drawing the 2D world, not from deleting it, and the user accepted the look at the rework gate, so deleting only removes cost (the hidden world's painting, its occluders and its capture) and the second set of tests that kept 2D drawing honest.

## Addendum: the pivot to a near top-down 3D that wears the 2D art (phase 2b, the look gate)

The first 3D look (the 35 degree isometric angle, flat-coloured solids, a blocky body) was rejected at the phase-2 gate: it did not look like the game. The render keeps the mirror, the hook and the pixel post, and changes what it looks like:

- **Near top-down, north up.** The camera pitch is 80 degrees (`RenderConfig.pitch_degrees`), not isometric and not a literal 90, so tops are the picture and the sides show a thin sliver. Q and E turn it in 90 degree steps (eased, resting only at north, east, south or west). 3D zoom snaps to whole steps (`Zoom3dConfig.steps`: 0.5, 1, 2, 3), so a picture pixel is a whole number of screen pixels and one art pixel is one picture pixel (`texel_match`): the texel is exact across and 98.5 percent (sin 80) down, so a row can crawl a texel while panning (measured: no flicker, and a quarter turn flickers on thin textured lines by the nature of rotating nearest-sampled pixel art). The turn's 2x supersample, planned as the shimmer mitigation, flickers 1.7 to 1.9 times more than none on textured art (averaging nearest-sampled art makes colours in no texel), so `turn_supersample` is 1.
- **The 2D art is the texture.** Each painter paints its piece unshaded (`render_flat`) and the mesh wears it (`MeshNodes.textured`: projected straight down on the top faces, the art's edge on the sides); the toon bands do the shading. A character is an upright, rounded body wearing the 2D head, shoulders, pack, fist, limb and shoe art, a gun the 2D gun art. Nothing in the painters was thrown away: they are the one source of the look in both modes.
- **The 2D render stays** (superseded: the next addendum deletes it).
- **Consequences:** a mesh that does not wear its piece's art reads as a plain slab beside the textured ones (the table was one until the look gate); a thing drawn as a solid part, a smoke puff, is a flat disc so it reads as the 2D blob, not a faceted dome; light is still the interim sun (phase 3 owns the 2D lights' look: coloured dusk, neon, flashes).
