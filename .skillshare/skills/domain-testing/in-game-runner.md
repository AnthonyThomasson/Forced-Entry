# The in-game and headed runner

Tests in a window. The headless runs are `SKILL.md`'s "Running tests".

- **`--shots`:** `tools/run_tests.sh --shots words` runs windowed and saves `<bundle dir>/<id with / as __>__fail.png` per failed test
  (printed as `shot:`); `t.bundle.screenshot(label)` saves one on demand (`""` when headless or `--shots` is off).
- **`--windowed`:** `tools/run_tests.sh --windowed [words]` runs gdUnit in a window with vsync off, always in one process
  (nothing competes with what it measures). A perf test's frame times then include the render. The draw tests that
  compare pixels run their image checks only this way (`tests/general/fill_batch_matches_draw_calls_test.gd`,
  `tests/items/prepaint_covers_the_draws_test.gd`, `tests/character/body_mesh_matches_polygons_test.gd`,
  `tests/physics/debris_pages_match_one_batch_test.gd`).
- **The browser:** the setup window's **Tests** button opens `test_browser.tscn`: search, pick, then Play. The runner plays
  the test with its result banner, keeps the world running and offers Rerun and Back (to `main.tscn`). Engine metas
  `test_selection` / `test_results` / `test_filter` survive the round trip through a test. **Run all** and each
  domain row's ▶ spawn `tools/run_tests.sh --no-lint` (Von tests replay; rows say `[Von replay]` or `[Von live-only]`) (`--domain=<name>`), console in
  `user://test_runs/<n>/run.log`, report folded into the browser's marks. `-- --play <filter>` on the command line opens
  the first matching test (a sandbox too) in the runner: launch `scenes/testing/test_runner.tscn` through Godot, since
  `run_tests.sh` refuses `--play`.
- **Headed queue:** tick tests in the browser and press **Run N checked**. The browser stores the ordered paths in the
  `test_queue` meta (`TestCatalog.META_QUEUE`, ticks in `META_CHECKED`) and the runner plays them one by one, each verdict
  held `QUEUE_PAUSE` (2 s, or until Next ▸). A failure does not stop the queue; Esc / Back cancels the rest.
- **Command-line queue:** `-- --queue=<id,id,…>` (through Godot, like `--play`) plays those ids in order; an id naming
  no test is printed and skipped, none valid opens the browser. It queues once per process (`META_CLI_QUEUED`), so
  Back → browser → Play plays the browser's pick. Each verdict prints as in a `run_tests.sh` run, then `Queue done:
  <summary>`.
- **`tools/play_tests.sh [ids…] [--base=REF]`** opens such a window, maximized, for a person to watch, and returns at
  once (fire and forget; the person closes it). With no ids it plays the change's tests: every `tests/**/*_test.gd`
  added or modified since the merge-base with `origin/main` (or `REF`), committed or not, never deleted ones, helpers or
  sandboxes. No tests: `nothing to play`, exit 2, nothing opened. One test window per worktree: a run first closes the
  window an earlier run opened (never the editor). The window owns its engine log (`--log-file <dir>/godot.log`,
  `--out=<dir>`, `<dir>` = `$TMPDIR/play_tests_<worktree>/`), so another Godot start neither hides an error from it nor
  lends it one (the shared `user://logs/godot.log` is never read, `log-gate.md`); lines
  logged while no test is open are listed before `Queue done:`. `show-me` runs it. Tested by `tools/test_play_tests.py`:
  run it after editing `play_tests.sh` or the runner's `--queue`.
- **Pause and overlays:** the banner's **Pause / Resume** (and Space, unless the test has a `player` actor, where Space
  is INTERACT) freezes the world; the test clock (`ctx.time`: waits and the timeout) stops with the tree. The runner keeps
  **Performance** (its own panel) and hands every other overlay toggle to `TestWorld.set_overlay`, which routes it by
  the match's one rule (`MatchBuilder.set_overlay`): Navigation holes to the world's `NavDebug`, Squad leaders to the
  `LeaderOverlay` of a world that declares squads or a match (none otherwise: the toggle does nothing), any NPC flag to
  the NPCs in the bar's scope, the actors' and a declared match's. The bar's **Show on** row offers `defenders`, `invaders` and `all` (default `all`; no `selected`: the runner has no detail card) and
  reaches `TestWorld.set_overlay_scope`, which re-applies every toggle at once.
- **Locking interactions:** `s.lock_interaction([&"camera", &"pause", &"overlays"])` in `configure` switches off what a
  person could do in a headed run that would change the result: `camera` drops wheel / trackpad / camera-key events and
  the hand-pan; `pause` hides Pause and ignores Space; `overlays` leaves out the overlay bar. A test that sends its own
  input uses `TestContext.inject(event)` (not bare `Input.parse_input_event`), which tags it so the lock lets it through;
  held keys are polled state and cannot be told apart. The browser's details pane lists "Locked while it runs".
