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
- **A district's steering tiles start baking a frame each and land together** (`nav_updater.gd`, `nav_tile_burst.gd` (`NavTileBurst`), `NavTiles.due_tiles` /
  `parse_for` / `prepare` / `land` / `walking_at`; `navigation/tile_rebake_one_a_frame`, `district_steering_rebake_lands_in_its_tick`): a tick's due tiles are started baking a frame each, each on a worker thread (`NavTiles.threaded_total`), and **landed in one**
  (`steering-edge-connections.md`). Order: tiles holding a **moving walker** first (a living character moving at `REST_SPEED` or more),
  by squared distance from the nearest walker to the tile's rect (0 inside it), then the rest, ties and a still scene in the grid's order, fixed at the tick.
  The tick starts the first (`prepare` gathers its source on the main thread), `_physics_process` one more a `GameClock` frame (none on a frame that started one), and the frame `NavBakeConfig.tile_frames` (3) after the last started `land`s them all, on a frame no bake landed on, slipping up to `MOST_SLIP` (3) then whatever (`NavTiles.late_total` counts a thread not done): k tiles land k-1+`tile_frames` frames after the tick's own; a walker sees a body that stopped up to that many frames later (accepted). A tile on its thread keeps its last mesh: no gap, still ready (`nav_ready_follows_the_tiles`). The walls are
  parsed once per burst. A lone house's region is baked whole in its tick, as are `rebake_steering` and `build`'s first.
  `tile_due_order` pins the order; a tick lands an open burst before reading what is due.
