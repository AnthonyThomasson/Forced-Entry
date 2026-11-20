---
name: domain-vision
description: Use when editing scenes/vision/, retuning the player's view (cone, memory, look, feather), asserting on it in a test, or adding a moving thing, overlay or light the view must treat.
---

# Vision domain (`scenes/vision/`)

The screen shows only what the human's character sees; the rest is the world as it stands, where it was last seen, in greyscale
(black where it never looked), and nothing that moves is drawn out of view. The spec is `docs/player-vision.md` (V1 to V12, each with its tests, which are in `tests/vision/`
through `tests/_vision/vision_probe.gd`); the numbers live in `VisionConfig` and the spec, not here; the decision is
`docs/adr/0011-the-vision-domain.md`. Interfaces: 7 (`sight()`, `facing`, `died`), 11 (`ViewLayers`, `SightRay`, `SeenArea`), 13 (the `vision.enabled` switch, `TestSetup.view`), 23 (the handle's `view`), 25 (this
domain's own).

A **leaf**, like Lighting: it imports General, Godot and Art's `ToonMask`, reads the viewer duck-typed (`global_position`, `facing`,
`sight()`, `is_dead`, the signals `died` and `tree_exiting`) and the world through the physics space and `get_surface()`. Its one
caller is `MatchBuilder` (`PlayerView.watch(world, character)`, for Main's human and the Testing world's viewer); nothing in
another domain knows `PlayerView`. Character, Items, Projectile, Physics and Vehicles set their own `ViewLayers` bits; the AI's
debug overlays, Navigation and the UI are overlays (`ViewLayers.overlay`); General holds `SightRay` and `SeenArea`.

| File | Role |
|---|---|
| `player_view.gd` (`PlayerView`) | The one node (group `player_view`): `watch` builds it, the two per-frame hooks, the lift, the test reads. |
| `view_cone.gd`, `view_shapes.gd`, `view_watch.gd` | The exact polygon (`ViewCone`, a job: `cone-job.md`), the blocking shapes round the eye (`ViewShapes`: a shape query, never a tree walk) and what says a rebuild is due (`ViewWatch`). Private. |
| `view_ground.gd` (`ViewGround`), `view_fan.gd`, `vision_ground_config.gd` (`VisionGroundConfig`) | The view: the live and seen masks, the triangle-fan painter both are drawn with (`ground.md`). |
| `vision_config.gd` (`VisionConfig`) | Tuning: the switch, the look, `feather`, the rays, `far_depth`, `far_bleed`, `rebuild_every`; the sliced rebuild's: `VisionSliceConfig`. |
| `view_pipeline.gd` (`ViewPipeline`) | Starts, steps, restarts and publishes the `ViewCone` job (`cone-job.md`). Private. |

What a character sees by (110° cone, 2520 px, a 48 px bubble, looking over what stands below its eye, 69 px standing and 32 ducked) is Character's `CharacterVisionConfig`,
read through `character.sight()`: any character can be the viewer.

## Each frame

- **Physics, priority 100** (after the characters have moved): `ViewPipeline.tick` steps the cone's job a slice (or starts one
  when `ViewWatch.stale` says so); a completed job writes `SeenArea.set_area(polygons, bounds)`. Written in the physics tick, read
  in `_process` (Art's `MeshCarrier` and `MeshFollower`, the shot layer), so what hides is decided on the frame's own area. **The cone shown is the exact
  cone of the pose its job started from, as old as its job** (V1 has the figures): tests compare to `published_pose()`.
- **`_process`:** `ViewGround.follow` keeps the live window about the camera (`Pointer.screen_transform`, interface 26); the masks'
  painters draw the cone polygon when a cone is published, the live one once per tap of the feather (32 shifted copies, a disc,
  laid inside the edge).
- **The cone** (`ViewCone`): a fan from the eye over ray ends sorted by angle. Rays: an even fan (`cone_rays` across the cone,
  `bubble_rays` round the eye) plus three at each corner of each blocking shape the eye sees (the corner's angle,
  `corner_offset` either side). `ViewShapes.corners` reads every solid shape touching the hull of the cone's sector and the bubble (`ViewCone._region`, grown 2 px) with a shape query (asked again with four
  times the cap while it comes back full: no blocker is dropped), splits them into blockers (a top above `see_over`, the viewer's eye) and
  lows, and dedupes corners to half a pixel, keeping the lesser (x, then y), whichever shape the engine names first. Every ray
  leaves the lows out and meets its first blocker in one cast (`SightRay` instance), then runs on to where it leaves it
  (`far_exit`: the farthest exit over the blocking shapes holding a point 0.1 px along the ray, so a wall or wardrobe seen shows
  its top; at most `far_depth`; `far_bleed` when it leaves through no edge; where no shape holds the point the ray only grazed
  and ends at the hit). The even fan is cast first, once (`_run_fan`) with a per-interval hide table (`_fan_hide`), and a corner between two fan rays that met the same convex shape nearer
  than it needs no ray (`vision/cone_hidden_corners_not_cast`), unless it lies within `FAN_HIDE_MARGIN` (0.25 px at its distance) of
  either ray: engine hits are off a face by up to 0.02 px (`vision/fan_hide_margin_keeps_grazing_corner`).
- **`ViewWatch` skips a rebuild** a fresh one would draw again, and a rebuild is due when any input of the cone changed: the eye,
  the facing, the sight numbers, the cone's `VisionConfig` numbers; the transform or collision layer of any blocker where a
  ray can pass (within the view distance, in the cone's sector or the bubble, each grown by the blocker's own extent and 2 px, measured when its shapes come or go and scaled by the largest absolute
  scale of its body; one wholly beyond it forces nothing), polled each frame, and the frame after a rebuild made while one moved;
  by signal a blocker's shapes coming or going (a dent or a wall re-cut frees shapes and adds new with no move of the body),
  leaving the tree, or a door's `changed`; a collider that entered the tree; a character that blocks (its posture covers more
  than the viewer looks over: rebuilt every frame it does, and the frame after); and every `rebuild_every` (10) frames, the
  backstop for a change it cannot see. `stale` asks all of it for the next job; `world_changed` all but the eye and facing, each
  tick of a job in flight (`cone-job.md`). The job length is the lag (V1). A low piece is in no ray, so it is not watched. A frame that rebuilds nothing measures no
  shape and builds no Array for the key (`vision/view_watch_suite` holds the first): keep it so.
- **A rebuild keeps what a plain one would re-read (#192; the polygon is vertex for vertex the reference's, `vision/cone_same_after_savings`).**
  `ViewShapes` keeps a non-character shape's world polygon across rebuilds, keyed by collider and shape index with the transform and
  shape resource it was made from: a move or a replaced shape misses, a dent, re-cut or in-place shape edit clears all of them
  (child-tree and `changed` signals), a collider leaving the tree drops its own; characters' polygons are read anew. In front of that sits a memo for
  one rebuild (`_memo`): a polygon is checked against its body once, then served from it (a rebuild asks about 1,300 times), and it is
  emptied by `reset()`, when polygons are cleared and when a collider leaves the tree, so it never serves a polygon across jobs. The check allocates
  nothing (the transform and the shape resource are compared in place). The far face (`far_exit(space, hit, dir)`) reads the blocking
  shapes holding the probe point afresh each ray: reusing the previous ray's polygons cost more than it saved (`docs/player-vision.md`).
  Angles are built without lambda sort/map; `polygon_reuses`, `memo_hits`, `validations` count for tests.
- **The look (V12):** two masks the toon shaders read (`ground.md`): the live window and the seen mask over the floors' bounds
  at `seen_scale` texels a px, never cleared; clear in the cone, the remembered world greyed outside, black unseen.
- **The lift:** `died` or `tree_exiting` on the viewer runs `SeenArea.clear()` at once and frees the view (its viewports) and clears the
  masks that frame; a viewer already dead gets no view (`watch` returns null). A view whose node is disabled (the perf guard's "off")
  clears `SeenArea` too, and the whole world is drawn again.

## Gotchas

- **A mover's place in the view is its sim node's `ViewLayers` bit, read by Art's `MeshCarrier` and `MeshFollower`**: a new moving thing sets
  `ViewLayers.set_moving` on its node (the mirror hides its mesh outside the cone) or, for a batch with no body, marks its mesh
  (`MeshNodes.moving`); a `MOVING` flash light is kept out of the world by nothing here: lights are Lighting's (`domain-lighting`).
- **`ViewShapes` keeps a collider's top for its life** (`_rated`: `SightRay.top_of`, its twin's top; a character's is 0, it is looked over at any height), and `ViewWatch` does not watch it. That
  holds because a piece's top is set once from its mesh's real size and a door's is always 84 with `transparent` fixed at spawn
  (`look.material == "glass"`; a shatter changes only `look.broken`). Objects promises neither changes in play (interface 03);
  the `rebuild_every` backstop bounds the stale cone should either ever change (a tipped piece, #194 D14). A collider with no twin yet
  (a body twins a frame after it joins) blocks like a wall and is asked again, not kept. A feature that changes either in play must tell
  `ViewShapes` and `ViewWatch`. The viewer's own posture changes what it looks over (`sight()["eye_height"]`): `ViewWatch` sorts every
  collider again when it changes, and the cone is rebuilt. A living character in the cone that the eye sees no point of is hidden by Art's
  mirror (`SeenArea.hides`, set by `_publish_area`), not by the cone.
- **A headless run draws no pixels**: a test holds what the masks are told (sizes, transforms, clear modes, the polygons the
  painters hold, `ToonMask`'s rects) and the pixels are read in a window (`vision/vision_mask_3d_windowed`, one test at a time).
  The view is always `ViewGround` (a test world builds it too).
- **A physics query right after a kinematic body's `global_position` is set sees it where it was** until the physics server is
  told at the next flush, so the view (priority 100) can read a body a mover (a door, a walker) moved this frame at its old
  place (`tests/_vision/physics_mover.gd` reproduces it). So `ViewWatch` rebuilds once more the frame after a rebuild made
  while a blocker within reach moved, and a cone built from a mover's old place holds for one frame (`vision/cone_skip_exact`).
- **`ViewCone.contains` (so `PlayerView.sees`) asks General's `SeenArea.contains`,** an even-odd rule, not the engine's
  `Geometry2D.is_point_in_polygon`, which says inside for points well outside a cone with many collinear corners along a wall
  (`tests/vision/view_sees_suite.gd` holds a counterexample). The test that judges what lies outside the cone
  (`vision/unseen_keeps_running`) keeps an even-odd copy of its own, so that it does not check the rule by itself.
- **The reference cone is a frozen yardstick:** `tests/_vision/reference_view_cone.gd` is the plainest form of the cone (it keeps
  nothing from one build to the next, reads every shape and coverage anew and casts every ray plainly); the tests compare the live
  cone to it vertex for vertex, so change it only with the spec (`docs/player-vision.md`, "Measured cost").
  Its far-face pick and corner dedupe do not depend on which overlapping shape the engine names, as the live cone's.
- **A viewport nested in another logs an engine error**: the live and seen viewports are siblings under the view's `Ground`.
- **The view costs the CPU of the cone and the masks' draw on request** (budget and numbers: `docs/player-vision.md`, "Measured
  cost"; the guards `perf/match_npc_vision` and `perf/match_npc_vision_relative`, `domain-testing` (`perf.md`)).
