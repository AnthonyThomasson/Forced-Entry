---
name: domain-vision
description: Use when editing scenes/vision/, retuning the player's view (cone, memory, look, feather), asserting on it in a test, or adding a moving thing, overlay or light the view must treat.
---

# Vision domain (`scenes/vision/`)

The screen shows only what the human's character sees; the rest is the world as it was last seen, in greyscale, and nothing that
moves is drawn out of view. The spec is `docs/player-vision.md` (V1 to V11, each with its tests, which are in `tests/vision/`
through `tests/_vision/vision_probe.gd`); the numbers live in `VisionConfig` and the spec, not here; the decision is
`docs/adr/0011-the-vision-domain.md`. Interfaces: 7 (`sight()`, `facing`, `died`), 11 (`ViewLayers`, `DrawLayers.VISION` /
`OVERLAY`, `SightRay`, `SeenArea`), 13 (the `vision.enabled` switch, `TestSetup.view`), 23 (the handle's `view`), 25 (this
domain's own).

A **leaf**, like Lighting: it imports General and Godot, reads the viewer duck-typed (`global_position`, `facing`, `get_rid()`,
`sight()`, `is_dead`, the signals `died` and `tree_exiting`) and the world through the physics space and `get_surface()`. Its one
caller is `MatchBuilder` (`PlayerView.watch(world, character)`, for Main's human and the Testing world's viewer); nothing in
another domain knows `PlayerView`. Character, Items, Projectile, Physics and Vehicles set their own `ViewLayers` bits; the AI's
debug overlays, Navigation and the UI are overlays (`ViewLayers.overlay`); General holds `SightRay` and `SeenArea`.

| File | Role |
|---|---|
| `player_view.gd` (`PlayerView`) | The one node (group `player_view`): `watch` builds it, the two per-frame hooks, the lift, the test reads. |
| `view_cone.gd`, `view_shapes.gd`, `view_watch.gd` | The exact polygon (`ViewCone`), the blocking shapes round the eye (`ViewShapes`: a shape query, never a tree walk) and what says a rebuild is due (`ViewWatch`). Private. |
| `view_memory.gd`, `view_fan.gd`, `view_mask.gd`, `view_composite.gd` | The capture and memory viewports and the wipe, the triangle-fan painter both painters are, the feathered mask, the composite over the world. Private. |
| `memory_paint`, `memory_wipe`, `view_composite` (`.gdshader`) | Paints the capture into the memory without blending; writes "nothing seen"; cuts the live world out and draws the memory in the look. |
| `vision_config.gd` (`VisionConfig`) | Tuning: the switch, the look, `feather`, `memory_scale`, the rays, `far_depth`, `far_bleed`, `rebuild_every`. |

What a character sees by (110° cone, 2520 px, a 48 px bubble, looking over coverage 60) is Character's `CharacterVisionConfig`,
read through `character.sight()`: any character can be the viewer.

## Each frame

- **Physics, priority 100** (after the characters have moved): `ViewWatch.stale(eye, facing, sight)`; when it says so,
  `ViewCone.rebuild` (cone and bubble), `ViewWatch.built`, then `SeenArea.set_area(polygons, bounds)`. Written in the physics
  tick, read in `_process` (Character's visuals, `BloodPool`), so a repaint is decided on the frame's own area.
- **`_process`:** the capture, memory, mask and composite follow the main viewport's canvas transform and size; the memory's
  painter paints the cone polygon from the capture, the mask's painter draws the polygon once per tap of the feather (32 shifted
  copies, a disc, laid inside the edge).
- **The cone** (`ViewCone`): a fan from the eye over ray ends sorted by angle. Rays: an even fan (`cone_rays` across the cone,
  `bubble_rays` round the eye) plus three at each corner of each blocking shape the eye sees (the corner's angle,
  `corner_offset` either side). `ViewShapes.corners` reads every solid shape touching the hull of the cone's sector and the bubble (`ViewCone._region`, grown 2 px) with a shape query (asked again with four
  times the cap while it comes back full: no blocker is dropped), splits them into blockers (coverage above `see_over`) and
  lows, and dedupes corners to half a pixel, keeping the lesser (x, then y), whichever shape the engine names first. Every ray
  leaves the lows out and meets its first blocker in one cast (`SightRay` instance), then runs on to where it leaves it
  (`far_exit`: the farthest exit over the blocking shapes holding a point 0.1 px along the ray, so a wall or wardrobe seen shows
  its top; at most `far_depth`; `far_bleed` when it leaves through no edge; where no shape holds the point the ray only grazed
  and ends at the hit). The even fan is cast first, once (`_cast_fan`), and a corner between two fan rays that met the same
  convex shape nearer than it needs no ray (`vision/cone_hidden_corners_not_cast`).
- **`ViewWatch` skips a rebuild** a fresh one would draw again, and a rebuild is due when any input of the cone changed: the eye,
  the facing, the sight numbers, the cone's `VisionConfig` numbers; the transform or collision layer of any blocker where a
  ray can pass (within the view distance, in the cone's sector or the bubble, each grown by the blocker's own extent and 2 px, measured when its shapes come or go and scaled by the largest absolute
  scale of its body; one wholly beyond it forces nothing), polled each frame, and the frame after a rebuild made while one moved;
  by signal a blocker's shapes coming or going (a dent or a wall re-cut frees shapes and adds new with no move of the body),
  leaving the tree, or a door's `changed`; a collider that entered the tree; a character that blocks (its posture covers more
  than the viewer looks over: rebuilt every frame it does, and the frame after); and every `rebuild_every` (10) frames, the
  backstop for a change it cannot see. A low piece is in no ray, so it is not watched. A frame that rebuilds nothing measures no
  shape and builds no Array for the key (`vision/view_watch_suite` holds the first): keep it so.
- **A rebuild keeps what a plain one would re-read (#192; the polygon is vertex for vertex the reference's, `vision/cone_same_after_savings`).**
  `ViewShapes` keeps a non-character shape's world polygon across rebuilds, keyed by collider and shape index with the transform and
  shape resource it was made from: a move or a replaced shape misses, a dent, re-cut or in-place shape edit clears all of them
  (child-tree and `changed` signals), a collider leaving the tree drops its own; characters' polygons are read anew. The far face
  (`far_exit(space, hit, dir)`) reuses the previous ray's blocker polygons when the hit is the same collider, shape and face normal,
  the probe point is strictly inside the kept polygon and no other blocking shape overlaps that shape. The angles are built without
  lambda sort or map. `far_reuses` and `polygon_reuses` count both for the test.
- **The look:** the capture shares the main world and leaves `MOVING` and `OVERLAY` out of its cull mask; the memory is a
  world-space `SubViewport` over the floors' bounds at `memory_scale` texels a px (less when the world is wider than 16 384),
  never cleared, wiped for its first two frames; the composite is a screen-sized polygon at `DrawLayers.VISION` (absolute, bit
  `OVERLAY`): clear inside the cone, the memory in the look outside it, black where nothing was seen.
- **The lift:** `died` or `tree_exiting` on the viewer runs `SeenArea.clear()` at once and frees the view (composite, viewports)
  that frame; a viewer already dead gets no view (`watch` returns null). A view whose node is disabled (the perf guard's "off")
  clears `SeenArea` too, and the whole world is repainted.

## Gotchas

- **A viewport draws a canvas item only if it and every ancestor share a bit with its `canvas_cull_mask`** (a windowed probe in
  4.4: parent 2 / child 1 under mask 6: the child is not drawn; parent 1 / child 2: neither; a `Control` on the default bit 1 is
  not drawn, also in a `CanvasLayer`). So the capture's mask drops a `MOVING` or `OVERLAY` node's whole subtree, and a mask that
  left out `WORLD` would drop the HUD, the world root and every child of a moving thing. That is why the main viewport draws
  every bit, and why the planned single world draw (the still world drawn once, in the capture) was dropped. Put a new moving
  thing's drawing in that node or its children, and never under a `WORLD` parent it does not share.
- **A `Light2D` ignores the cull mask** and `visibility_layer`: a `MOVING` flash would still light the capture and be remembered.
  The flash pool sits under a `CanvasLayer` the capture does not draw (`domain-lighting`).
- **`ViewShapes` keeps a non-character collider's coverage for its life** (`_rated`), and `ViewWatch` does not watch it. That
  holds because a piece's coverage is set once in `ObjectFactory` and a door's is always 100 with `transparent` fixed at spawn
  (`look.material == "glass"`; a shatter changes only `look.broken`). Objects promises neither changes in play (interface 03);
  the `rebuild_every` backstop bounds the stale cone should either ever change. A feature that changes either in play must tell
  `ViewShapes` and `ViewWatch`. A character's coverage follows its posture, so it is read each build and `ViewWatch` rechecks
  characters every frame.
- **The headless test viewport is 64×64**, and the capture, mask and composite take its size. A test that needs a screen
  sizes the root viewport first; the pixels are judged by eye in a window.
- **A physics query right after a kinematic body's `global_position` is set sees it where it was** until the physics server is
  told at the next flush, so the view (priority 100) can read a body a mover (a door, a walker) moved this frame at its old
  place (`tests/_vision/physics_mover.gd` reproduces it). So `ViewWatch` rebuilds once more the frame after a rebuild made
  while a blocker within reach moved, and a cone built from a mover's old place holds for one frame (`vision/cone_skip_exact`).
- **`ViewCone.contains` (so `PlayerView.sees`) asks General's `SeenArea.contains`,** an even-odd rule, not the engine's
  `Geometry2D.is_point_in_polygon`, which says inside for points well outside a cone with many collinear corners along a wall
  (`tests/vision/view_sees_suite.gd` holds a counterexample). The test that judges which repaints `SeenArea` allows
  (`vision/unseen_not_repainted`) keeps an even-odd copy of its own, so that it does not check the rule by itself.
- **The reference cone is a frozen yardstick:** `tests/_vision/reference_view_cone.gd` is the plainest form of the cone (it keeps
  nothing from one build to the next, reads every shape and coverage anew and casts every ray plainly); the tests compare the live
  cone to it vertex for vertex, so change it only with the spec (`docs/player-vision.md`, "Measured cost").
  Its far-face pick and corner dedupe do not depend on which overlapping shape the engine names, as the live cone's.
- **A viewport nested in another logs an engine error**: the capture, memory and mask are siblings under the view.
- **The view costs the CPU of the cone and the viewports' scene work** (budget and numbers: `docs/player-vision.md`, "Measured
  cost"; the guards `perf/match_npc_vision` and `perf/match_npc_vision_relative`, `domain-testing` (`perf.md`)).
