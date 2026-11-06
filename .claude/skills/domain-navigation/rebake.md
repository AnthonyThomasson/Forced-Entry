# Navigation: keeping the holes current

Side file of `domain-navigation` (`SKILL.md`).

A bake is a snapshot, and furniture is shoved in play. `nav_updater.gd` (built once by `MatchBuilder.stage` right after the bake,
handed the region, house, rooms and the overlay) recomputes `furniture_holes` and `character_holes` each `interval` (cheap:
transforms only) and re-bakes **only** when something moved past `move_threshold`: furniture re-bakes both regions (the planning
one on the server's worker thread; a tick while it is in flight leaves the planning region alone, and
the baseline is set from what the bake carved when it lands, so a move during a bake is caught by the next tick); a character that
stopped, set off, appeared or died re-bakes the steering region in place. An at-rest scene costs the compare.

- The tick's own re-bakes take the footprints it just measured, so it measures furniture
  once and parses the walls once. The public `rebake`,
  `rebake_async`, `rebake_steering` are **test-facing seams** that measure their own footprints; only tests call them.
- `rebake` re-bakes a region's polygon in place with holes re-measured at the furniture's **current** `global_transform`.
  `rebake_async` gathers the geometry on the main thread and assigns the polygon when the bake lands, then runs `done`; the
  callback holds the region by a `WeakRef` (a lambda capturing a node freed before it runs logs an engine error:
  `tests/navigation/rebake_outlives_region_test.gd`). The sync `rebake` is for a test that needs the map now
  (`perf/bake_and_path_stress` times it); no frame pays for a bake.
- `furniture_holes` keeps each body's hull with what it was made from, so only a piece that moved,
  turned or was dented is measured again (`furniture_holes_follow_the_pieces_test.gd`); the simplified outline is pinned to the plain
  version by `outline_simplify_matches_plain_test.gd`. Tile binning likewise remembers an outline's bounds by its contents:
  unchanged outlines cost no new measurement, while any moved point makes a fresh key.
- After each re-bake, and again when the planning one lands, it calls the overlay's `setup` so the overlay re-snapshots.
- **Between re-bakes bulldozing is the behaviour** (and for non-solid decor, never carved): a piece just shoved is run over by the
  character's push physics until the next re-bake routes round its new position.

Any `NavigationAgent2D` pathfinds against the map automatically; the AI's locomotion sets `target_position` and steers at
`get_next_path_position()`, and leaves the agent's RVO avoidance off.
