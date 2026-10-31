# Errors and warnings fail the test (`log_watch.gd`)

Godot 4.4 has no in-process logger hook (`OS.add_logger` arrives in 4.5), so `LogWatch` tails the engine log file (the run's
`--log-file`, else `debug/file_logging/log_path`) from an offset marked as the run or runner starts, and parses
`ERROR:` / `SCRIPT ERROR:` / `USER ERROR:` / `WARNING:` headers with their `at:` lines.

- **Inside a test:** the session (`test_session.gd`: the in-game runner and every gdUnit suite) polls it every physics
  frame and hands each entry to the open test (`verdict.on_log`). An expected (`t.verdict.expect_log`) or allowed
  (`allowed_logs`, or the global `[von] ` launcher diagnostics) line passes; anything else is a failed check
  `Logged error: … (at …)` that ends the test at once. A native suite case (`UnitSuite`) reads the log after it ends,
  two physics frames on. Teardown logs count too: the session frees the world and polls again before the verdict.
- **Outside a test:** lines logged while no test is open (a test script's parse error when the catalog loads it) fail the
  run (`Logged outside any test`). A `run_tests.sh` process owns a fresh log, so the watch starts at byte 0 and start-up
  errors count. gdUnit's own log scan (`report/godot/script_error`) is off in `project.godot`: it reads the project's
  log path, not the run's, and would blame a test for another Godot's errors.
- **Nothing escapes the process:** the run writes `log_end` (`LogWatch.consumed()`) into its report; the wrapper then
  scans the log from there to the end with `tools/scan_godot_log.py` (gdUnit's reports, shutdown), from byte 0 when no
  report exists (`--list`, a crash). Any hit fails the run. Godot's end-of-process leak report ("ObjectDB instances
  leaked", "resources still in use at exit") is a `NOTE` unless `--strict-exit`: a character together with a reflectively
  read config holder such as `CharacterStunConfig` prints it whatever the test does. `tools/load_check.sh` applies the same
  gate to a plain headless start-up.
- **Headless or windowed:** the gate reads a file, so it is the same either way. The in-game runner started otherwise
  (`-- --play …`, the browser) and a GdUnit panel run watch the default log (`debug/file_logging/enable_file_logging`),
  shared by every Godot start of the project, so a start elsewhere rotates it and can hide an error. In-game, a logged
  error fails the open test and flips a verdict already shown.
- **Tested by** `tools/test_log_gate.py` (`--headed` adds the windowed engine): the scanner on crafted logs, `run_tests.sh`
  around a fake Godot for every way a run can end, and the real engine through the harness probes in `tests/_harness/`
  (`log_gate_probe_test.gd`, `GAME_TEST_PROBE=error|warning`; `verdict_probe_test.gd`, `gap_probe_test.gd`,
  `von_probe_test.gd`, `warning_hold_probe_test.gd`; `log_watch_offsets_test.gd` for the read positions). Run it after
  editing `log_watch.gd`, `test_session.gd`, `test_batch.gd`, `game_test_suite.gd`, `unit_suite.gd`,
  `test_report_hook.gd`, `run_tests.sh`, `scan_godot_log.py`, `tools/lint*` or `gdstyle.toml` (it also tests the lint: its
  probes are written into a copy of the checkout, `copy_checkout()`; `GdStyleLintTests` holds every `quality/*` rule of
  `gdstyle.toml` in one of two rows, on or off by decision). `tools/test_gdunit_wrap.py` runs gdUnit's own discovery
  (`tools/gdunit_discover.gd`) and checks that every catalog test is one wrapper case, by id, and the harness tests are in
  the self-test suite alone: run it after adding or moving a suite. `tools/test_gdunit_panel.py`: `gdunit-panel.md`.
