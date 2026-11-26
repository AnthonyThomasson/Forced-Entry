# Navigation: keeping the holes current

Side file of `domain-navigation` (`SKILL.md`).

A bake is a snapshot, and furniture is shoved in play. `nav_updater.gd` (built once by `MatchBuilder.stage` right after the bake,
handed the region, house, rooms and the overlay) recomputes `furniture_holes` and `character_holes` each `interval` (cheap:
transforms only; `start()` starts its timer) and re-bakes **only** when something moved past `move_threshold`: furniture re-bakes both regions (the planning
one gathered and baked off the frame, below; a tick while it is in flight leaves the planning region alone, and
the baseline is set from what the bake carved when it lands, so a move during a bake is caught by the next tick); a character that
stopped, set off, appeared or died re-bakes the steering region in place. An at-rest scene costs the compare.

- **A district's planning gather is sliced** (`nav_gather.gd`; `sliced_rebake_matches_whole`): the tick (itself sliced: `tick.md`) re-bakes the steering
  tiles and starts a `NavGather`, whose steps run one a physics frame from the updater's `_physics_process` (the walls' parse, the
  furniture holes (the ring's too) fused on worker threads (started by step one, joined `FUSE_STEPS` (4) frames on, inline if it never began: `NavFuse`), the district's job, the ring's: seven steps, so seven frames from the tick's own, the swap in the last). The jobs are a second
  buffer nothing reads: until the last step the region's polygon, the map's iteration and the remembered source (`NavSource.remember`) are
  the previous bake's. The last step `NavRebake.swap`s it in whole (the source is remembered, the planning and ring bakes go to a worker thread (`NavBake`), landing on their fixed frame, a
  `done` once both land: the baseline is set then), so the swap is the one moment a finished re-bake shows (the `remember` version counts
  them, the map iterations follow when the bakes land; route caches and the AI's lead-route memo key on those). `_baking` holds from the
  tick's `_apply` (it starts the gather, if the footprints still move against the baseline as it stands: a bake that landed meanwhile carved them) to the landing: a move meanwhile waits for the next tick. A lone house's
  gather stays in its tick (`_rebake_planning`, walls shared with its steering bake). The fusing (`NavUnion`, on a worker) is nine tenths
  of the gather.
- **A bake lands on a fixed frame** (`nav_bake.gd`, `nav_bake_config.gd`; `navigation/rebake_lands_on_its_frame`, `avoid_map_lands_on_its_frame`,
  `rebake_waits_for_a_late_thread`, `landings_one_a_frame`, `perf/nav_rebake_lands_in_a_match`). One a frame: a bake due on a taken frame slips to the next, in start order (a planning bake's ring after it). `NavRebake._bake_async` and `NavBuilder._bake_avoid` start the bake on a
  `WorkerThreadPool` task through `NavBake.start`, which takes its result in (assign to the region, `landed`) on the physics
  frame the caller's count says after the thread's start (the ask, unless it waited its turn, below), not when it finishes. A thread not done by then is waited for, which holds that frame (`NavBake.was_late` of that bake, `late_total` of all; the match
  guards log `PERF <label> nav bakes late N of M, gather fusings late K`); on time costs the frame its assignment only. `NavBake.frames_for(region, avoid, ring)`
  picks the count from `NavBakeConfig`, a district's planning bake `district_frames` 36 (a 120 to 140 ms thread; `perf/ambush_order_stress` sets 50: its frames are 3 ms), its avoid
  maps `avoid_frames` 22 (the AI waits on a chain), the planning ring `ring_frames` 7
  (a 14 ms thread, an `urgent` job: a high-priority task, never queued behind busy threads), a lone house's bakes `house_frames` 3.
  Remeasure when a bake or a frame changes. A region freed meanwhile is left
  alone and `landed` still called; a game closing finishes every bake in flight.
- **A bake waits its turn** (`nav_turns.gd` (`NavTurns`); `navigation/bakes_wait_their_turn`, `crowded_bakes_are_not_late`,
  `held_bake_nobody_asks_for_is_dropped`, `held_avoid_bake_takes_the_newest_source`, `ring_bake_takes_no_turn`,
  `freed_waiting_bake_never_starts`). Every bake but the urgent ring's holds one of
  `NavBakeConfig.at_once` (3) places from start to landing. One asked with none free is not started: it starts at the landing that frees
  one, **oldest first** (district and avoid alike), and counts from there, so it lands later instead of holding a frame. None starves:
  with `q` waiting ahead it starts within `q / 3 + 1` times the longest count (plus the one-a-frame slips); with none piled up nothing
  changes. **A held avoid map can miss its reader:** a hold asks its body maps `WARM_LEAD` (36 frames) ahead and the count is 22,
  so one held over 14 frames lands late (match guards: held 1 to 32 frames, 22 and 32 among them). The reader then gets -1 for a
  first bake (one more pulled re-plan, ~0.6 s) or, for a re-bake, the OLD mesh with `ready` true; a dropped re-bake leaves the old
  mesh answering until asked again. 32 is a sample, not a bound: `q` is uncapped (3 places per 22 frames; a redone planning bake
  re-queues every map asked again; door-view maps are never dropped; the district's bake waits in the same line).
  A waiting avoid bake is made from the planning source as it is when it starts (a planning re-bake meanwhile is in it, no second bake). `avoid_map(…, repeats = true)` (a hold's body maps,
  asked every beat while wanted): a waiting one nobody asked for in `held_ask_frames` (4) when its turn comes is dropped, and the next
  ask bakes it (without this a burst of moved bodies queued maps nobody read: 168 frames late). A bake whose region is gone holds no
  place, and a waiting one is never started (nothing carries over from a torn-down world).
  **The limit:** 3 is the pool's width for normal-priority tasks on a 10 to 13 thread machine (0.3 of the threads, rounded down), a fixed
  number so every machine lands a bake on the same frame. Below 10 threads (an 8-thread box runs 2, a 4-thread one 1) a started bake can
  still queue in the pool, as can one on any machine behind the sound and pixel-art pre-warms just after a world starts; its
  landing then waits for it as before this rule. From 14 threads up the rule is narrower than the pool.
- **A map syncs on the main thread** (`project.godot`, `navigation/world/map_use_async_iterations` off; `navigation/map_syncs_without_a_thread`): the server's
  async sync would show a landed bake on a frame that follows the machine's load, so a match was a different fight run to run whatever the landing frames.
  It costs the main thread within 0.4 ms of the async average.
- The tick's own re-bakes take the footprints it just measured, so it measures furniture
  once and parses the walls once. The public `rebake`,
  `rebake_async`, `rebake_steering` are **test-facing seams** that measure their own footprints, like `NavUpdater.tiles_in_play`; tests only.
- `rebake` re-bakes a region's polygon in place with holes re-measured at the furniture's **current** `global_transform`.
  `rebake_async` gathers the geometry on the main thread and assigns the polygon on the bake's fixed frame, then runs `done`; the
  landing holds the region by a `WeakRef` (a lambda capturing a node freed before it runs logs an engine error:
  `tests/navigation/rebake_outlives_region_test.gd`).  The sync `rebake` is for a test that needs the map now.
- After each re-bake, and again when the planning one lands, it calls the overlay's `setup` so the overlay re-snapshots.
- **Between re-bakes bulldozing is the behaviour** (and for non-solid decor, never carved): a piece just shoved is run over by the
  character's push physics until the next re-bake routes round its new position.

Any `NavigationAgent3D` pathfinds against the map automatically; the AI's locomotion sets `target_position` and steers at
`get_next_path_position()`, and leaves the agent's RVO avoidance off.
