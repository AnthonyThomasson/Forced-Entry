# Perf · What the player's view costs, held as a difference

`perf/match_npc_vision_relative` (read from `perf.md`; the numbers' story is `docs/player-vision.md` "Measured cost"): one 10v10 in
one process, blocks of frames with the view working and blocks with it switched off (node disabled, viewports not rendering),
interleaved on, off, off, on, because two plays of the match differ from each other by far more than the view costs.

- It holds the median difference to `BUDGET_MS` and the live cone's cost to `RATIO_MAX` of the reference cone's from the same eye
  (`tests/_vision/reference_view_cone.gd`).
- Its moving rounds hold `MOVING_BUDGET_MS`, 8.5 ms (about 1.4x the moving mean of about 6 ms after #192's Extension 3, 4.60 and
  5.61; was 20), which departs from the 4x rule: 4x of a per-frame cost would never trip. Headless sees the CPU side only.
- `perf/match_npc_vision` is the absolute standard on the same match.
