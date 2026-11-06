# Errors and warnings fail the test (`log_watch.gd`)

Godot 4.4 has no in-process logger hook (`OS.add_logger` arrives in 4.5), so `LogWatch` tails the engine log file **this
process owns** from an offset marked as the run or runner starts, and parses `ERROR:` / `SCRIPT ERROR:` / `USER ERROR:` /
`WARNING:` headers with their `at:` lines. Its own log is the `--log-file <file>` it was started with, read off its own
command line before any `--` (the engine strips the flag from `OS.get_cmdline_args()`: `/proc/self/cmdline`, else
`ps`; none on Windows), or `path_override`. It never reads the default `user://logs/godot.log`: every Godot start of the
project writes it and each start rotates it by copying and truncating it, so no byte of it is one process's, and other
starts' exit errors (`p_elem->_root != this`, `ObjectDB instances leaked`) would read as this test's. With no
`--log-file` it reads nothing: `available()` is false and the runner prints `NOTE: this process has no engine log of its
own (start it with --log-file <file>) - errors and warnings will NOT fail this test`.

- **Inside a test:** the session (`test_session.gd`: the in-game runner and every gdUnit suite) polls it every physics
  frame and hands each entry to the open test (`verdict.on_log`). An expected (`t.verdict.expect_log`) or allowed
  (`allowed_logs`, or the global `[von] ` launcher diagnostics) line passes; anything else is a failed check
  `Logged error: … (at …)` that ends the test at once. A native suite case (`UnitSuite`) reads the log after it ends,
  two physics frames on. Teardown logs count too: the session frees the world and polls again before the verdict.
- **Outside a test:** lines logged while no test is open (a test script's parse error when the catalog loads it) fail the
  run (`Logged outside any test`). A `run_tests.sh` process owns a fresh log, so the watch starts at byte 0 and start-up
  errors count. gdUnit's own log scan (`report/godot/script_error`) is off in `project.godot`: it reads the project's
  log path, not the run's, and would blame a test for another Godot's errors.
- **Open handle:** `begin` keeps the log open and each physics-frame poll queries and reads that handle rather than reopening it.
  A shorter length or a change in the remembered 64-byte tail before the read offset reopens it and reads from the start, so
  truncation and in-place rewrites are seen; appends reuse the handle. `log_watch_offsets_test.gd` pins all three cases.
- **Nothing escapes the process:** the run writes `log_end` (`LogWatch.consumed()`) into its report; the wrapper then
  scans the log from there to the end with `tools/scan_godot_log.py` (gdUnit's reports, shutdown), from byte 0 when no
  report exists (`--list`, a crash). Any hit fails the run. Godot's end-of-process leak report ("ObjectDB instances
  leaked", "resources still in use at exit") is a `NOTE` unless `--strict-exit`: a character together with a reflectively
  read config holder such as `CharacterStunConfig` prints it whatever the test does. `tools/load_check.sh` applies the same
  gate to a plain headless start-up.
- **Headless or windowed:** the gate reads a file, so it is the same either way. The in-game runner started any other way
  watches only the log it was given: a hand start takes `--log-file <file>`; the game the editor's Play starts has one
  when `tools/editor.sh` opened the editor (`GAME_LOG_FILE`, made the game's `--log-file` by `addons/ticket_autorun`,
  and the game `editor.sh --autorun` opens beside an editor already up: `$TMPDIR/game_<worktree>.engine.log`). A bare
  `-- --play …`, the Tests button from a game started without one and a GdUnit panel run have none and print the NOTE
  (console and banner). In-game, a logged error fails the open test and flips a verdict already shown.
- **Tested by** `tools/test_log_gate.py` (`--headed` adds the windowed engine): the scanner on crafted logs, `run_tests.sh`
  around a fake Godot for every way a run can end, and the real engine through the harness probes in `tests/_harness/`
  (`log_gate_probe_test.gd`, `GAME_TEST_PROBE=error|warning`; `verdict_probe_test.gd`, `gap_probe_test.gd`,
  `von_probe_test.gd`, `warning_hold_probe_test.gd`; `log_watch_offsets_test.gd` for the read positions). `tools/tests/test_runner_own_log.py` runs the real engine in a
  copy of the checkout with a `user://` of its own: a bare `-- --play` reads none of another start's errors and prints
  the NOTE, and a start with `--log-file` still fails on its own error after another start rotated the default log
  (`GAME_TEST_PROBE_AFTER=<file>` holds the probe until then). Run it after
  editing `log_watch.gd`, `test_session.gd`, `test_batch.gd`, `game_test_suite.gd`, `unit_suite.gd`,
  `test_report_hook.gd`, `run_tests.sh`, `scan_godot_log.py`, `tools/lint*` or `gdstyle.toml` (it also tests the lint: its
  probes are written into a copy of the checkout, `copy_checkout()`; `GdStyleLintTests` holds every `quality/*` rule of
  `gdstyle.toml` in one of two rows, on or off by decision). `tools/test_gdunit_wrap.py` runs gdUnit's own discovery
  (`tools/gdunit_discover.gd`) and checks that every catalog test is one wrapper case, by id, and the harness tests are in
  the self-test suite alone: run it after adding or moving a suite. `tools/test_gdunit_panel.py`: `gdunit-panel.md`.
