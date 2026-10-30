## The GdUnit panel (editor)

gdUnit4 5.1.1 (`addons/gdUnit4/`, plugin on) adds a **GdUnit** dock to the editor. `project.godot`'s `[gdunit4]` section
points its lookup at `tests/` with discovery on, so it lists every suite there: the 27 wrapper suites, the harness's
`tests/_harness/harness_suite.gd` and the native suites. A wrapper suite holds one parameterized test (`test_projectile`)
whose cases are its folder's catalog tests, one per id: `test_projectile:3 ('projectile/pistol_shot_wounds')`. They are
read from the folder's `*_test.gd` files, so a new test shows up with no edit to the suite.

- **One case or one suite:** right-click it in the dock's tree, then **Run** or **Debug** (breakpoints stop in the test).
  A suite file can also be run from the FileSystem dock's context menu (**Run Testsuites**), and a case from the script
  editor's (**Run Tests**).
- **Everything:** the toolbar's **Run overall tests** button (shown by `ui/toolbar/run_overall`).
- **Watching:** gdUnit runs the tests in a game window of its own and minimises it; the base suite restores it whenever
  a test's world is built and frames the world with the game camera, as the in-game runner does.
- **What differs from `run_tests.sh`:** no options reach the suites, so nothing is selected away: every case is listed,
  the harness's own included, and `requires_von` tests run (the Von server is started or reused; skipped when none comes
  up). Verdicts map as on the command line (FAIL / TIMEOUT failed, SKIPPED / GAP skipped), with the failed checks as the
  failure message; bundles go to `user://test_failures/` and no `report.json` is written. The log gate watches the
  project's own log from the run's start, which another Godot start (the game, `tools/lint.sh`) can rotate, as in the
  in-game runner started from the browser.
- **Stepped like the command line:** every way the panel runs (Run and Debug on a case or a suite, Run overall) starts
  gdUnit's editor runner (`GdUnitTestRunner.tscn`, as its own process or through the editor's Play) without
  `--fixed-fps`, so the engine paces it to the clock. Left so, a slow frame is caught up with several physics frames in
  one main-loop iteration before its process frame (a draw test's overlay, updated in `_process`, then shows nothing
  after `t.frames(2)`), and vsync holds each frame to the display. The session hook (`test_report_hook.gd`) sees the
  editor's runner (the `GdUnitRunner` engine meta's script) and steps it once an iteration
  (`Engine.max_physics_steps_per_frame` 1) with vsync off, both put back at the session's end; a lagging panel run then
  slows its sim rather than catching up, as under `--fixed-fps`, and a frame budget measures the iteration a frame ran
  in (`Perf.frame_stats`), not the pacing waits between. So a panel run gives the verdicts of
  `tools/run_tests.sh --windowed`, its perf numbers included: some frame budgets do not hold windowed on this machine
  yet (Performance tests, "Rendered too"), so a perf test the panel fails is one `--windowed` fails too; `tests/_harness/frame_step_test.gd` checks the stepping (each physics frame waited
  brings a process frame, after slow frames).
- **Reports out of the checkout:** gdUnit writes a run's JUnit and HTML reports to `res://reports/` unless given `-rd`
  (`run_tests.sh` always gives it, the panel never does); the hook moves a run left on that default to
  `user://gdunit_reports/report_<n>/` (a folder given with `-rd` stays as given). The run config the panel writes before each run
  (`addons/gdUnit4/GdUnitRunner.cfg`: the cases and its server's port) is gitignored, so a panel run leaves
  `git status` clean.
- **Tested by** `tools/test_gdunit_panel.py`: `tools/gdunit_panel.gd` does what the panel's Run does without an editor
  (gdUnit's discovery, its TCP server, the run config, the runner started with the panel's arguments, stopped when its
  session closes as the editor stops it) on a scratch copy of the checkout with its own `user://`. Headless: the
  harness's `frame_step` and the two draw tests pass, the reports land in `user://gdunit_reports/`, no `reports/`
  appears and every file the run writes is ignored. `--headed` (a window; perf wants a quiet machine) adds the nine
  timing tests, the two draw tests and the two click tests (`ui/command_menu_items`, `ui/inspector_outfit`). Run it
  after editing `test_report_hook.gd`, `perf_probe.gd` or gdUnit's runner settings.
