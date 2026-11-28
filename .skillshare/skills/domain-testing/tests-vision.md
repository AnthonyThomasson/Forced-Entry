# Vision tests (domain `vision`, `tests/vision/`)

The rules are `docs/player-vision.md` (V1 to V12, each with its tests named under it); `tools/run_tests.sh --domain=vision` runs them.
The helper is `tests/_vision/vision_probe.gd` (`const Probe`; not a test): it reads a `PlayerView` only through the reads interface 25
publishes (`cone()`, `bubble()`, `sees(point)`, `viewer()`, `ground` and its viewports and painters), keeps the spec's numbers as consts (`FOV`,
`REACH`, `BUBBLE`, `SEE_OVER`, the visibility bits), and builds the shared two-room layout (`building`), a world of the test's own
(`build_world` / `drop_world`) and the sight rule cast directly (`blocker`, `in_sight`), which the cone tests judge the polygon by.
It also holds the points the sees tests ask (`WALL_CONE`, `OUTSIDE`, shared with General's `seen_area_suite`) and `reached_by`,
which says whether `SeenArea` reaches a point by a disc or by a box. Beside it: `changing_body.gd` (a solid that can say `changed`, as
a door does), `physics_mover.gd` and `cone_checker.gd`. `vision/view_watch_suite` is a native suite of `ViewWatch`'s rule at its own
seam (bodies in the tree, `stale` asked each frame), beside the simulation tests that hold the cone itself.

- **The view is off unless a test turns it on.** The Testing switch `vision.enabled` (`VisionConfig.enabled`) has a row `default` of
  false, so no other test or sandbox draws through a view. A test that wants one calls `s.switch(&"vision.enabled", true)`; the world
  then views its `player` actor, or the actor `s.view(id)` names (any character, an NPC included: viewing changes nothing in its AI).
  A declared match with a human gets its view from `MatchBuilder.populate` instead.
- **A headless run has no pixels.** The tests hold what the parts are told (the masks' sizes, transforms and clear modes, the polygon a
  painter holds, `ToonMask`'s rects, `visibility_layer`s) and the geometry (the polygon against `SightRay` cast directly); the look is
  read in a window (`vision/vision_mask_3d_windowed`, `art/toon_vision_hook_windowed`: `tools/run_tests.sh --windowed --id=`, one at a
  time, they use `RenderingServer.force_draw`). A test world's view builds `ViewGround`, as Main's 3D view does (the test world builds no 3D scene). **Every vision rule stands on data or on
  the masks, never on a 2D draw**: a rule that only the 2D drawing showed (a repaint skipped for the unseen) has no test.
- **Premise first.** Each geometry test counts what it samples (the points behind corners, the shapes in reach, the frames compared)
  and `require`s a floor, so a test that sampled nothing fails instead of passing. `cone_exact_with_many_blockers` counts more solid
  shapes in reach than any fixed query cap; `unseen_keeps_running` shoots one walker out of the cone in a viewed world
  and an unviewed one and compares the hits.
- **Compare against a fresh rebuild, vertex for vertex.** `tests/_vision/reference_view_cone.gd` and `reference_view_shapes.gd`
  are the plainest form of the cone (it keeps nothing from one build to the next, reads every shape and coverage anew and casts
  every ray plainly, with the determinism rules of `docs/player-vision.md`). `cone_same_after_savings` holds the live cone to it
  over a grid of eyes and facings in generated houses and after a door, a shove and a freed piece; `cone_skip_exact` runs
  `cone_checker.gd` after the view every physics frame: in a frame the view published a cone it must be the polygon a fresh rebuild
  draws **from the published pose**, not the viewer's live one (`PlayerView.published_pose()`, `docs/player-vision.md` V1: the cone
  is as old as its job); in any other frame it must be the cone held before. `cone_age.gd` says how old the cone is
  (`vision/pose_lag_bounds` pins that). The cone is a job of a few frames only with a small slice: a test that needs that sets
  `VisionSliceConfig.slice_units` (140 for the test houses, with `cost_shape` set to the same 140: the corners fill a slice there; the default price of the corners, about 200 units, is below the default slice), `cone_skip_exact_sliced` is `cone_skip_exact` at 140, and a test that
  reads the cone of a pose waits for it (`Probe.place`), never a fixed count of frames. A "rebuilt every frame" premise counts
  `starts()` (a job begun or restarted), not `rebuilds()` (published) (`physics_mover.gd` moves a body from its own `_physics_process`, as a door or a walker moves: a query later in that frame,
  the view's, still finds it where it was).
- **Perf:** `perf/match_npc_vision` and `perf/match_npc_vision_relative` (`perf.md`): the 10v10 with the view on an NPC (`s.view`).
