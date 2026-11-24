# Navigation: keeping the holes current

Side file of `domain-navigation` (`SKILL.md`).

A bake is a snapshot, and furniture is shoved in play. `nav_updater.gd` (built once by `MatchBuilder.stage` right after the bake,
handed the region, house, rooms and the overlay) recomputes `furniture_holes` and `character_holes` each `interval` (cheap:
transforms only; `start()` starts its timer) and re-bakes **only** when something moved past `move_threshold`: furniture re-bakes both regions (the planning
one gathered and baked off the frame, below; a tick while it is in flight leaves the planning region alone, and
the baseline is set from what the bake carved when it lands, so a move during a bake is caught by the next tick); a character that
stopped, set off, appeared or died re-bakes the steering region in place. An at-rest scene costs the compare.

- **A district's planning gather is sliced** (`nav_gather.gd`; `sliced_rebake_matches_whole`): the tick re-bakes the steering
  tiles at once and starts a `NavGather`, whose steps run one a physics frame from the updater's `_physics_process` (the walls' parse, the
  furniture holes fused on a worker thread (started by the first step, joined `FUSE_STEPS` (4) frames on, inline if it never began: `NavFuse`), the district's job, the ring's: seven steps, so seven frames from the tick's own, the swap in the last). The jobs are a second
  buffer nothing reads: until the last step the region's polygon, the map's iteration and the remembered source (`NavSource.remember`) are
  the previous bake's. The last step `NavRebake.swap`s it in whole (the source is remembered, the planning and ring bakes go to a worker thread (`NavBake`), landing on their fixed frame, a
  `done` once both land: the baseline is set then), so the swap is the one moment a finished re-bake shows (the `remember` version counts
  them, the map iterations follow when the bakes land; route caches and the AI's lead-route memo key on those). `_baking` holds from the
  tick to the landing: a move meanwhile waits for the next tick. A lone house's
  gather stays in its tick (`_rebake_planning`, walls shared with its steering bake). The fusing (`NavUnion`, on a worker) is nine tenths
  of the gather.
- **A district's steering tiles start baking a frame each and land together** (`nav_updater.gd`, `nav_tile_burst.gd` (`NavTileBurst`), `NavTiles.due_tiles` /
  `parse_for` / `prepare` / `land` / `walking_at`; `navigation/tile_rebake_one_a_frame`, `district_steering_rebake_lands_in_its_tick`): a tick's due tiles are started baking a frame each, each on a worker thread (`NavTiles.threaded_total`), and **landed in one**
  (`steering-edge-connections.md`). Order: tiles holding a **moving walker** first (a living character moving at `REST_SPEED` or more),
  by squared distance from the nearest walker to the tile's rect (0 inside it), then the rest, ties and a still scene in the grid's order, fixed at the tick.
  The tick starts the first (`prepare` gathers its source on the main thread), `_physics_process` one more a `GameClock` frame (none on a frame that started one), and the frame `NavBakeConfig.tile_frames` (3) after the last started `land`s them all (`NavTiles.late_total` counts a thread not done): k tiles land k-1+`tile_frames` frames after the tick; a walker sees a body that stopped up to that many frames later (accepted). A tile on its thread keeps its last mesh: no gap, still ready (`nav_ready_follows_the_tiles`). The walls are
  parsed once per burst. A lone house's region is baked whole in its tick, as are `rebake_steering` and `build`'s first.
  `NavTiles.baked_total` counts tiles baked, not landed. `tile_due_order` pins the order; a tick lands an open burst before reading what is due.
- **A bake lands on a fixed frame** (`nav_bake.gd`, `nav_bake_config.gd`; `navigation/rebake_lands_on_its_frame`, `avoid_map_lands_on_its_frame`,
  `rebake_waits_for_a_late_thread`, `landings_one_a_frame`, `perf/nav_rebake_lands_in_a_match`). One a frame: a bake due on a taken frame slips to the next, in start order (a planning bake's ring after it). `NavRebake._bake_async` and `NavBuilder._bake_avoid` start the bake on a
  `WorkerThreadPool` task (the server's sync bake) through `NavBake.start`, which takes its result in (assign to the
  region, `landed`) on the physics frame the caller's count says after the start, not when the thread finishes. A thread not done by then is waited for, which holds that frame (`NavBake.was_late` of that bake, `late_total` of all; the match
  guards log `PERF <label> nav bakes late N of M, gather fusings late K`); on time costs the frame its assignment only. `NavBake.frames_for(region, avoid, ring)`
  picks the count from `NavBakeConfig`, a district's planning bake `district_frames` 36 (a 120 to 140 ms thread; `perf/ambush_order_stress` sets 50: its frames are 3 ms), its avoid
  maps `avoid_frames` 22 (the AI waits on a chain), the planning ring `ring_frames` 7
  (a 14 ms thread, an `urgent` job: a high-priority task, never queued behind busy threads), a lone house's bakes `house_frames` 3.
  Later than the 2D baker's (planning 14, avoid 12): open work.
  Remeasure when a bake or a frame changes. A region freed meanwhile is left
  alone and `landed` still called; a game closing finishes every bake in flight (`NavBake._finish_all`).
- **A map syncs on the main thread** (`project.godot`, `navigation/world/map_use_async_iterations` off; `navigation/map_syncs_without_a_thread`): the server's
  async sync would show a landed bake on a frame that follows the machine's load, so a match was a different fight run to run whatever the landing frames.
  It costs the main thread almost nothing: within 0.4 ms of the async average (`domain-testing`, its perf side files).
- The tick's own re-bakes take the footprints it just measured, so it measures furniture
  once and parses the walls once. The public `rebake`,
  `rebake_async`, `rebake_steering` are **test-facing seams** that measure their own footprints, like `NavUpdater.tiles_in_play`; tests only.
- `rebake` re-bakes a region's polygon in place with holes re-measured at the furniture's **current** `global_transform`.
  `rebake_async` gathers the geometry on the main thread and assigns the polygon on the bake's fixed frame, then runs `done`; the
  landing holds the region by a `WeakRef` (a lambda capturing a node freed before it runs logs an engine error:
  `tests/navigation/rebake_outlives_region_test.gd`). The sync `rebake` is for a test that needs the map now
  (`perf/bake_and_path_stress` times it); no frame pays for a bake.
- `furniture_holes` (`NavHoles.furniture`, one `NavPieces` tracker per house) keeps each piece's hull with what it was cut from (its twin
  and the twin's pose, `NavTwins.stamp_of`), and cuts only a piece whose twin moved, turned or tipped, or that was twinned or added; a
  quiet tick reads one transform a piece and walks no tree. A footprint a script moves by hand reaches the twin up to
  `TwinSpace.PARK_SPREAD` frames later. The pieces are found again (`find_children`) only after one
  was added under the house (`SceneTree.node_added`) or left it, so the order is a walk's. `NavHoles.plain` cuts every piece afresh, the reference
  (`furniture_holes_cache_matches_recut_test.gd`, `furniture_holes_follow_the_pieces_test.gd`; `NavHoles.walks` and `cuts` count the work);
  the simplified outline is pinned to the plain
  version by `outline_simplify_matches_plain_test.gd`. Tile binning likewise remembers an outline's bounds by its contents:
  unchanged outlines cost no new measurement, while any moved point makes a fresh key.
- After each re-bake, and again when the planning one lands, it calls the overlay's `setup` so the overlay re-snapshots.
- **Between re-bakes bulldozing is the behaviour** (and for non-solid decor, never carved): a piece just shoved is run over by the
  character's push physics until the next re-bake routes round its new position.

Any `NavigationAgent3D` pathfinds against the map automatically; the AI's locomotion sets `target_position` and steers at
`get_next_path_position()`, and leaves the agent's RVO avoidance off.
