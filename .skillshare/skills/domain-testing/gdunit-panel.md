# The GdUnit panel (editor)

gdUnit4 (`addons/gdUnit4/`, plugin on) adds a **GdUnit** dock to the editor. `project.godot`'s `[gdunit4]` section points
its lookup at `tests/`, so it lists every suite: the wrapper suites, `tests/_harness/harness_suite.gd` and the native
suites. A wrapper suite holds one parameterized test whose cases are its folder's catalog tests, one per id, read from the
folder's `*_test.gd` files, so a new test needs no edit to the suite.

- **Run:** right-click a case or suite in the dock's tree (**Run** or **Debug**: breakpoints stop in the test), the
  FileSystem dock's **Run Testsuites**, the script editor's **Run Tests**, or the toolbar's **Run overall tests**.
- **What differs from `run_tests.sh`:** no options reach the suites, so nothing is selected away: every case is listed,
  the harness's own included, and `requires_von` tests replay their recordings (one without a recording, or a `live_only` one, runs live: the server is
  started or reused, skipped when none comes up). Verdicts map as on the command line (FAIL / TIMEOUT failed, SKIPPED / GAP skipped). Bundles go to
  `user://test_failures/`, no `report.json` is written, and the log gate watches the project's own log from the run's start,
  which another Godot start (the game, `tools/lint.sh`) can rotate.
- **Stepped like the command line:** gdUnit's editor runner starts without `--fixed-fps`, so the engine would pace it to
  the clock: a slow frame is caught up by several physics frames in one iteration (a draw test's overlay, updated in
  `_process`, shows nothing after `t.frames(2)`), and vsync holds each frame. The session hook (`test_report_hook.gd`)
  recognises the editor's runner (the `GdUnitRunner` engine meta) and steps it once an iteration
  (`Engine.max_physics_steps_per_frame` 1) with vsync off, both put back at the session's end. So a panel run gives the
  verdicts of `tools/run_tests.sh --windowed`, perf numbers included (`perf.md`, "Rendered too"):
  a perf test the panel fails is one `--windowed` fails too. `tests/_harness/frame_step_test.gd` checks the stepping.
- **Reports stay out of the checkout:** gdUnit writes JUnit and HTML to `res://reports/` unless given `-rd`
  (`run_tests.sh` always gives it); the hook moves a default-location run to `user://gdunit_reports/report_<n>/`. The run
  config the panel writes (`addons/gdUnit4/GdUnitRunner.cfg`) is gitignored.
- **Tested by** `tools/test_gdunit_panel.py` (`tools/gdunit_panel.gd` does what the panel's Run does without an editor, on
  a scratch copy of the checkout; `--headed` adds the timing, draw and click tests: `ui/command_menu_items`, `ui/inspector_right_click_card`). Run it after editing
  `test_report_hook.gd`, `perf_probe.gd` or gdUnit's runner settings.
