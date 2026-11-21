# The in-game and headed runner

Tests in a window. The headless runs are `SKILL.md`'s "Running tests".

- **`--shots`:** `tools/run_tests.sh --shots words` runs windowed and saves `<bundle dir>/<id with / as __>__fail.png` per failed test
  (printed as `shot:`); `t.bundle.screenshot(label)` saves one on demand (`""` when headless or `--shots` is off).
- **A test world shows the game:** in the in-game runner (browser, `--play`, `--queue`, `play_tests.sh`, a sandbox) and in a `--shots` run the session builds Main's 3D view over the built world (`TestSession.picture`, `_show_picture`: the world's 2D picture is hidden, its overlays lie flat over the 3D one, the lights are the dusk's), after the host framed its camera. A headless run builds none (no pixels to draw); a batch run with a window (`--windowed`, `--shots`) builds it as the runner does (`GameTestSuite.before`), except a perf test, which measures its own render (`_harness/window_picture_windowed`). A test that builds its own `View3D` lights it (`light_world`) and a probe asserts its frame is not black (`perf/render_3d_post_cost`): an unlit view draws outlines on black. A test that builds its own picture declares `s.own_picture()`. The picture shows only the open test's world: a test that declares none stands on the default arena, and when it builds a house or district of its own into the world the session leaves that arena out of the picture (`MeshCarrier.leave_out`, `MeshFollower.leave_out`; test `_harness/session_picture`); a test that declares a world and builds another beside it shows both. Only a world staged in the test's own twin space (29) has a picture: geometry a test generates by hand and never stages (`worldgen/district_facings`, `ai/perception/house_look_cadence`'s stand-ins) has no twins to mesh, and a match built in a world of its own (`MainProbe.viewport`, a 64 px `SubViewport` with 3D off, one per sweep step: `general/match_spawn_team_beside_front_door`) is another physics world, so the window shows the default arena: say so, do not look for a seam. An `own_picture` test draws in the window only when its own `View3D` is a child of the root (`general/twin_*_picture_windowed`, `follower_draws_loose_things_windowed`: seen, 160+ colours in a sampled frame); the rest (Main whole or a view inside a `SubViewport`, read back as a texture: `general/render_3d_match_windowed`, the `*_mesh(_windowed)` set, `lighting/light_3d_*`) draw into an off-screen target, so the window stays the root's grey by design (surveyed windowed with a flat-colour probe, #194 blanktest); there is no one seam, since each target is the test's own (its size, its update mode, what it reads back). A test that reads an NPC's debug overlays asks `GroundLayer.overlays_of(npc)` (or `OverlayRegistry.overlays_of`), not its children (the picture moves them under the ground layer; an overlay made at the build is moved once the picture shows), and a test that makes its own `Camera2D`, `CameraRig` or view declares `own_picture()` too: run it with `tools/run_tests.sh --shots` to see.
- **A windowed test reads its picture after `RenderingServer.force_draw(false)`, never `await RenderingServer.frame_post_draw`:** a window the desktop covers is not drawn and never signals it (the test runs its clock out, or reads a black frame).
- **`--windowed`:** `tools/run_tests.sh --windowed [words]` runs gdUnit in a window with vsync off, always in one process
  (nothing competes with what it measures). A perf test's frame times then include the render. The draw tests that
  compare pixels run their image checks only this way (`tests/vision/vision_mask_3d_windowed_test.gd`).
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
