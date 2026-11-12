# Perf · finding what costs, and gotchas

Side file of `perf.md` (split out to keep it under the 8192-byte cap).

- **Attribute by timing:** a frame's wall time is script time. A throwaway `Time.get_ticks_usec` accumulator around the
  suspect functions (never committed), dumped at the end of the measured window, ranks them in minutes; switching a
  feature off with `set_static` / `switch` shows what it is worth. Measure before reading: a per-frame cost is rarely
  where the code suggests.
- A lambda captures ints by value (count into an Array).
- `nav.rebake` is off in tests that shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync
  error); the match guards keep it on and allow that log (`MATCH_LOGS`).
- World-gen's first run in a process is slower (cold caches), so its budget covers the cold case.
- Headless runs skip the sound pre-warm: a test that plays sound calls `Perf.warm_sounds()` first or turns `audio.sound`
  off, or the first play of each variant lands in its worst frame.
- A district holds hundreds of pieces, so a script callback on each is a cost of every frame (it lengthens every process group a match sorts and walks): a piece's visuals and its blood smear run none while it rests (`objects/resting_piece_runs_no_per_frame_callback`, `physics/object_smear_sleeps_at_rest`).
- A speed-up must not change what the game does: where a fast path replaces a plain algorithm, a test pins its output to
  the plain one (`navigation/furniture_union_fast_path`, `physics/blood_splat_merge_fast_path`,
  `physics/convex_pieces_match_plain_scan`, `physics/shape_polygon_cache`).
