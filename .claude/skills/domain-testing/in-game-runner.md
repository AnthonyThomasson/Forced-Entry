# The in-game and headed runner

Running tests in a window: `SKILL.md`'s "Running tests" covers the headless runs.

- **`--shots`:** `tools/run_tests.sh --shots words` runs windowed (not headless) and saves
  `<bundle dir>/<id>__fail.png` for each failed test (printed as `shot:`); `t.bundle.screenshot(label)` saves one
  on demand (returns "" when headless or `--shots` is off). Read the PNG to see what went wrong.
- **`--windowed`:** `tools/run_tests.sh --windowed [words]` runs gdUnit in a window with vsync off (`--disable-vsync`), always in one
  process (no shard competes with what it measures, and one window), headless staying the default. A perf test's frame times then
  include the render, without being held to the display's refresh; the draw tests that compare pixels
  (`general/fill_batch_matches_draw_calls`, `items/prepaint_covers_the_draws`, `character/body_mesh_matches_polygons`,
  `physics/debris_pages_match_one_batch`) run their image checks only this way.
- **In game:** the setup window's **Tests** button opens `test_browser.tscn`. Search, pick, then Play,
  double-click or Enter. The runner plays it with the result banner, keeps the world running, and
  offers Rerun and Back/Escape (Back changes scene to `main.tscn`, the setup window). The in-game overlay toggle bar works on the test's NPCs.
  `-- --play <filter>` on the command line opens the first matching test straight in the runner (launch
  `test_runner.tscn` through Godot: `tools/run_tests.sh` only runs batches and refuses `--play` with that command).
  The browser's **Run all** button, and the ▶ button on each domain row (which passes `--domain=<name>`),
  spawn `tools/run_tests.sh --include-von --no-lint` for the whole suite or just that domain, Von tests included
  (they skip if no server comes up), its console in `user://test_runs/<n>/run.log` and its merged report there
  (`--report=user://test_runs/<n>/report.json`), show elapsed time, then fold that report into the marks (only
  the ids in it change) and the status line. Failure bundles stay in the run's own temp dirs, whose `bundle:` paths
  `run.log` prints. The buttons are disabled while a run is going.
- **Headed queue:** tick tests in the browser (checkbox per test, bulk buttons per domain and in the header; they
  respect the search) and press **Run N checked**. The browser stores the ordered paths in the `test_queue` meta
  (`TestCatalog.META_QUEUE`; the ticks themselves are `test_checked`, `META_CHECKED`) and opens the runner, which
  plays them one by one in the real window: each verdict is held `QUEUE_PAUSE` (2 s, or until the banner's Next ▸),
  then the world is freed and the next test starts. A failure does not stop the queue; Esc/Back cancels the rest.
  Results fold into the browser's marks as for a single Play; a summary shows after the last test.
- **Command-line queue:** `-- --queue=<id,id,…>` (launch `test_runner.tscn` through Godot, like `--play`) plays those
  exact ids as the headed queue above, in the order given: harness tests allowed, an id that names no test printed
  (`No test with id '<id>' (skipped)`) and skipped, none valid -> the browser. It queues once per process (the runner's
  `META_CLI_QUEUED` meta), so Back -> browser -> Play plays the browser's pick. Each verdict line is printed as in a
  `run_tests.sh` run, and after the last test `Queue done: <summary>` (the banner's summary). **`tools/play_tests.sh [ids…]
  [--base=REF]`** opens such a window, maximized (the camera centres each test's bodies, so its clicks sit clear of the
  result banner at the top-left), for a person to watch: with no ids, **the change's tests** (every
  `tests/**/*_test.gd` added or modified since the merge-base with `origin/main`, or `REF`: committed, uncommitted and
  untracked; not deleted ones, helpers or sandboxes), by id; with ids, those in that order. No tests: it says so
  (`nothing to play`), exits 2 and opens nothing. One test window per worktree: a run first closes the window an
  earlier run opened (pid in `$TMPDIR/play_tests_<worktree>.pid`, killed only while it is still this checkout's
  queued runner), never the editor or its game. The window owns its engine log as a `run_tests.sh` process does: it is launched
  with `--log-file <dir>/godot.log` and `--out=<dir>`, `<dir>` = `$TMPDIR/play_tests_<worktree>/` emptied each run, so
  another Godot start (an editor's game, `tools/lint.sh`, another worktree's window), which rotates the shared
  `user://logs/godot.log`, cannot hide an error from it; the runner watches that log from its start, so start-up errors
  count (lines logged while no test is open are listed before `Queue done:`, which adds `, N logged outside any test`).
  Fire and forget: it launches the window detached (`GAME_TICKET` set, importing a fresh worktree first), prints the
  queued ids, `test window pid <pid> | log <dir>/godot.log` (the verdict and `Queue done:` lines) and returns; the
  person closes the window. `show-me` runs it. **Tested by** `tools/test_play_tests.py` (a fake Godot in a temporary
  git repo for the selection, exit 2, one window, the return and the window's own log dir, then the real engine
  headless for `--queue`, and a window the script launches failing the log-gate probe while another Godot starts on
  the project mid-queue); run it after editing `play_tests.sh` or the runner's `--queue`.
- **Pause and overlays (headed runs):** the banner's **Pause / Resume** (and Space, unless the test has a `player`
  actor, where Space is INTERACT) freezes the world. The runner stays `PROCESS_MODE_ALWAYS`, each `TestWorld` is
  explicitly pausable, and the test clock (`ctx.time`, so waits and the timeout) stops with the tree; the tree is
  always unpaused on a new test, Back and exit. The overlay bar works on the test's NPCs: the runner keeps
  **Performance** (its own panel) and hands every other toggle to `TestWorld.set_overlay`, which routes it by the match's one rule
  (`MatchBuilder.set_overlay`): **Navigation holes** to the world's `NavDebug` (built by `MatchBuilder.stage`, kept current by the
  re-baker), **Squad leaders** to the `LeaderOverlay` of a world that declares squads or a match (none otherwise, so the toggle does
  nothing there), and any NPC flag to every NPC, its actors' and a declared match's.
- **Locking interactions:** `s.lock_interaction([&"camera", &"pause", &"overlays"])` in `configure` switches off
  what a person could do in a headed run that would change the result. `camera` drops the user's wheel /
  trackpad / camera-key events and the runner camera's hand-pan; `pause` hides the Pause button and ignores
  Space; `overlays` leaves out the overlay bar. A test that sends its own input must use
  `TestContext.inject(event)` (not bare `Input.parse_input_event`), which tags it so the lock lets it through.
  Held keys are polled state and cannot be told apart. The five `tests/general/camera_*_test.gd` use it; the
  browser's details pane lists "Locked while it runs".
