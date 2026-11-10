# Navigation: keeping the holes current

Side file of `domain-navigation` (`SKILL.md`).

A bake is a snapshot, and furniture is shoved in play. `nav_updater.gd` (built once by `MatchBuilder.stage` right after the bake,
handed the region, house, rooms and the overlay) recomputes `furniture_holes` and `character_holes` each `interval` (cheap:
transforms only) and re-bakes **only** when something moved past `move_threshold`: furniture re-bakes both regions (the planning
one gathered and baked off the frame, below; a tick while it is in flight leaves the planning region alone, and
the baseline is set from what the bake carved when it lands, so a move during a bake is caught by the next tick); a character that
stopped, set off, appeared or died re-bakes the steering region in place. An at-rest scene costs the compare.

- **A district's planning gather is sliced** (`nav_gather.gd`, `navigation/sliced_rebake_matches_whole`): the tick re-bakes the steering
  tiles at once and starts a `NavGather`, whose steps run one a physics frame from the updater's `_physics_process` (the walls' parse, the
  furniture holes fused in `FUSE_STEPS` (4) chunks, the district's job, the ring's: seven steps, so seven frames after the tick's own and the swap in the last, under the 8-frame cap). The jobs are a second
  buffer nothing reads: until the last step the region's polygon, the map's iteration and the remembered source (`NavSource.remember`) are
  the previous bake's. The last step `NavRebake.swap`s it in whole (the source is remembered, the planning and ring bakes go to a worker thread (`NavBake`), landing on their fixed frame, a
  `done` once both land: the baseline is set then), so the swap is the one moment a finished re-bake shows (the `remember` version counts
  them, the map iterations follow when the bakes land; route caches and the AI's lead-route memo key on those). `_baking` holds from the
  tick to the landing: a move meanwhile waits for the next tick. A torn-down match (`_alive()`) drops the gather. A lone house's
  gather stays in its tick (`_rebake_planning`, walls shared with its steering bake). The fusing (`NavUnion`, fed in chunks) is nine tenths
  of the gather.
- **A bake lands on a fixed frame** (`nav_bake.gd`, `nav_bake_config.gd`; `navigation/rebake_lands_on_its_frame`, `avoid_map_lands_on_its_frame`,
  `rebake_waits_for_a_late_thread`, `perf/nav_rebake_lands_in_a_match`). `NavRebake._bake_async` and `NavBuilder._bake_avoid` start the bake on a
  `WorkerThreadPool` task (the server's sync `bake_from_source_geometry_data`) through `NavBake.start`, which takes its result in (weld, assign to the
  region, `landed`) on the physics frame the caller's count says after the start, not when the thread finishes (`domain-testing`: the perf
  nondeterminism note). A thread not done by then is waited for, which holds that frame (`NavBake.was_late` of that bake, `late_total` of all; the match
  guards log `PERF <label> nav bakes late N of M`); one on time costs the frame its weld and assignment only. `NavBake.frames_for(region, avoid, ring)`
  picks the count from `NavBakeConfig`: a district's planning bake `district_frames` 14 (the p95 of its thread on the 5v5 guard's 7 ms frame), its avoid
  maps `avoid_frames` 12 (the p90: the AI waits for a chain of them, so each link costs the count; 10, near the median, was late for a quarter of them), the planning ring `ring_frames` 3
  (a 4 to 7 ms bake), a lone house's bakes `house_frames` 3. The measurements, and why the avoid maps' is not the same, are the holder's comments.
  Remeasure when a bake or a frame changes (a scratch log of the frames from `NavBake.start` to the thread's completion). A region freed meanwhile is left
  alone and `landed` still called; a game closing finishes every bake in flight (`NavBake._finish_all`).
- **A map syncs on the main thread** (`project.godot`, `navigation/world/map_use_async_iterations` off; `navigation/map_syncs_without_a_thread`): the server's
  async sync would show a landed bake on a frame that follows the machine's load, so a match was a different fight run to run whatever the landing frames.
- The tick's own re-bakes take the footprints it just measured, so it measures furniture
  once and parses the walls once. The public `rebake`,
  `rebake_async`, `rebake_steering` are **test-facing seams** that measure their own footprints; only tests call them.
- `rebake` re-bakes a region's polygon in place with holes re-measured at the furniture's **current** `global_transform`.
  `rebake_async` gathers the geometry on the main thread and assigns the polygon on the bake's fixed frame, then runs `done`; the
  landing holds the region by a `WeakRef` (a lambda capturing a node freed before it runs logs an engine error:
  `tests/navigation/rebake_outlives_region_test.gd`). The sync `rebake` is for a test that needs the map now
  (`perf/bake_and_path_stress` times it); no frame pays for a bake.
- `furniture_holes` (`NavHoles.furniture`, one `NavPieces` tracker per house) keeps each piece's hull with the transform it was cut at, and
  cuts only a piece that moved or turned (its transform), was dented (its colliders are rebuilt: a child shape came or went, which marks it)
  or was added; a quiet tick reads one transform a piece and walks no tree. The pieces are found again (`find_children`) only after one
  was added under the house (`SceneTree.node_added`) or left it, so the order is a walk's. A collider moved, resized or re-shaped in place
  (not rebuilt as a new child) is not seen (nothing does it). `NavHoles.plain` cuts every piece afresh, the reference
  (`furniture_holes_cache_matches_recut_test.gd`, `furniture_holes_follow_the_pieces_test.gd`; `NavHoles.walks` and `cuts` count the work);
  the simplified outline is pinned to the plain
  version by `outline_simplify_matches_plain_test.gd`. Tile binning likewise remembers an outline's bounds by its contents:
  unchanged outlines cost no new measurement, while any moved point makes a fresh key.
- After each re-bake, and again when the planning one lands, it calls the overlay's `setup` so the overlay re-snapshots.
- **Between re-bakes bulldozing is the behaviour** (and for non-solid decor, never carved): a piece just shoved is run over by the
  character's push physics until the next re-bake routes round its new position.

Any `NavigationAgent2D` pathfinds against the map automatically; the AI's locomotion sets `target_position` and steers at
`get_next_path_position()`, and leaves the agent's RVO avoidance off.
