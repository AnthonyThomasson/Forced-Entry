# A district's tick, sliced, and what a landing costs

`nav_tick.gd` (`NavTick`), `nav_due.gd` (`NavDue`), `NavPieces.Reader`; tests `tick_sliced_equals_whole`, `burst_waits_for_a_bake_landing`.

- **The tick is a job** (a district only; a lone house ticks at once, `rebake.md`). The timer starts a `NavTick`; the updater's
  `_physics_process` runs one step a frame: the pieces' footprints (`NavPieces.reader`: a cursor of its own, a `holes` read between steps leaves it alone; `NavTick.SCAN` 500 pieces read and
  `CUTS` 32 cut a step, so the cold first tick, where every piece is cut afresh, spreads too), the characters' footprints and the
  move checks, then the due tiles (`NavDue`: `OUTLINES` 400 binned by the tiles' reaches and `TILES` 16 checked a step). The counts are
  work, not time. Run to its end it finds what a tick made at once finds (`tick_sliced_equals_whole`).
- **WHEN moves.** The pieces are read over the steps, so a later slice reads its pieces a frame later; the baselines, the burst's start
  (`_apply`) and the planning gather come about nine frames after the timer fires (a cold tick, 857 pieces all cut: 27 or more). A tick found
  still running when the timer fires again is skipped (`busy()`, `ticking()` are the test seams). Measured on the 10v10 opening's window
  (A/B at load 300): the first tick was 18 to 67 ms in one frame (the guard's max frame #13), the worst step now 7 to 10 ms there at that
  load (the cold tick's cuts).
- **What the tick meets** (`tick_meets_the_world`). `_apply` starts the gather only if the footprints still move against the baseline as it stands: a
  planning bake that landed during the tick carved them already. A disabled updater starts nothing from a tick it had running.
- **A landing, one a `GameClock` frame.** Every landing assigns polygons and makes its map synchronise. `NavBake` takes a frame for a
  bake's landing (`landing_taken`, `take_landing`), and a steering burst's landing (`NavTileBurst.step`) is due on a frame no bake took or
  waits one, up to `MOST_SLIP` (3), and takes its frame, a forced one (`land`) too (the bake's signal runs before the updater's step). A tile's border seams (`NavSeams.read`) are read on its worker, so the
  landing only keeps them. What a landing costs now: `NavSeams.weld` about 1 ms, 5 to 6 ms at load on a landing where a tile is baked
  again with its neighbour's cells closed (`_agree` re-bakes on the main thread: the cost left), the assignment 0.1 ms, the join only when
  a worker is late (`NavTiles.late_total`). The planning bake's landing is the assignment and the engine's map step.
