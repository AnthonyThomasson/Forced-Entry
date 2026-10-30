## Errors and warnings fail the test (`log_watch.gd`)

Godot 4.4 has no in-process logger hook (that arrives with `OS.add_logger` in 4.5). `LogWatch` tails
the engine log file (`debug/file_logging/log_path`, or the run's own `--log-file`) from an offset marked as the run
or the runner starts, and parses
`ERROR:` / `SCRIPT ERROR:` / `USER ERROR:` / `WARNING:` / … headers with their `at:` lines.

- The test session (`test_session.gd`, under the in-game runner and under each gdUnit suite) polls it every physics
  frame and hands each entry to the open test (its context's `verdict.on_log(ctx, entry)`).
  An expected (`t.verdict.expect_log`) or allowed (`allowed_logs`, or the global `[von] ` launcher diagnostics)
  line passes; anything else is a failed check, `Logged error: … (at …)`, and ends the test at once (under gdUnit too,
  not at its timeout). A native suite's test (`UnitSuite`) reads the log after it ends, two physics frames on, and
  fails on any entry.
- Teardown logs count too. The session frees the world and polls again before taking the verdict;
  the in-game runner re-renders the banner if a late error arrives.
- Lines logged while no test is open (for example a test script's parse error when the catalog loads
  it) fail the run (`Logged outside any test`). The run's own output never starts with an error header. A
  `run_tests.sh` process owns a fresh log (`--log-file` + `--out`), so the watch starts at byte 0 and **start-up errors
  count too**. gdUnit's own log scan (`report/godot/script_error`) is off in `project.godot`: it reads the project's log
  path, not the run's, so it would blame a test for another Godot's errors.
- **Nothing escapes the process either.** The run writes `log_end` (bytes judged, `LogWatch.consumed()`) into its
  report; `tools/run_tests.sh` then scans the log from there to the end with `tools/scan_godot_log.py` — whatever
  the engine writes after it, gdUnit's own reports and the shutdown — and from byte 0 when no report exists (`--list`,
  a crash, a run that never started), once per shard. Any hit prints `Logged outside any test` and fails the run. Godot's own
  end-of-process leak report ("ObjectDB instances leaked at exit", "resources still in use at exit") is a `NOTE`
  by default (`--strict-exit` fails it): runs that touch a character together with a reflectively read config
  holder such as `CharacterStunConfig` print it at exit whatever the test does. `tools/load_check.sh` applies the same
  gate to a plain headless start-up.
- **Headless or windowed.** The gate reads the log file, so it is the same either way: `tools/run_tests.sh --shots`
  runs gdUnit with a window, and a `tools/play_tests.sh` window follows its own log (`--log-file` + `--out`) as a
  `run_tests.sh` process does. The in-game runner started otherwise (`-- --play …`, the browser), and a run from the
  GdUnit panel, watch the default log
  (`debug/file_logging/enable_file_logging` is set in `project.godot`), shared by every Godot start of the project, so a
  start elsewhere rotates it and can hide an error from it. In-game, a logged error or warning fails the
  open test and flips a verdict already shown; each verdict is also printed to the console, and the banner says so
  when the log cannot be read.
- **Tested by** `tools/test_log_gate.py` (`--headed` adds the windowed engine): the scanner on crafted logs,
  `run_tests.sh` around a fake Godot for every way a run can end and for how it starts gdUnit (headless, `--fixed-fps
  60`, a log per process), and the real engine through the harness probes: `log_gate_probe_test.gd` (set
  `GAME_TEST_PROBE=error|warning`) in a `run_tests.sh` run and in-game, and the gdUnit verdicts (PASS, FAIL, TIMEOUT,
  SKIPPED, GAP skipped as "gap: expected to fail", a passing gap a failure, a logged warning ending its test at once,
  a Von test with no server), the lines, summary, `report.json`, bundles and gdUnit's JUnit / HTML reports, and a native
  suite run in a copy with a fresh `user://`; `log_watch_offsets_test.gd` covers the read positions. Run it after
  editing `log_watch.gd`, `test_session.gd`, `test_batch.gd`, `game_test_suite.gd`, `unit_suite.gd`,
  `test_report_hook.gd`, `run_tests.sh` or `scan_godot_log.py`. The same file tests the lint: `lint_report.py` on
  crafted logs, `run_tests.sh` stopping on a lint failure, the real engine through `tools/lint.sh` (the project is
  clean; a probe script's warnings are found) and the gdstyle pass on probe scripts (an unformatted one and a line over
  100 columns fail; `GdStyleLintTests`' quality table puts every `quality/*` rule of `gdstyle.toml` in one of two
  rows, on or off by decision, and lints a probe per rule on, which fails naming it, and per rule off by
  decision, which passes, each probe clean with every quality rule off and breaking its own alone with every one on),
  each probe written into a copy of the checkout (`copy_checkout()`). Run it after editing
  `tools/lint*` or `gdstyle.toml` too. `tools/test_gdunit_wrap.py` runs
  gdUnit's own discovery (`tools/gdunit_discover.gd`) and checks that every catalog test is one wrapper case, by id,
  and the harness tests are in the self-test suite alone: run it after adding or moving a suite.
  `tools/test_gdunit_panel.py` runs the tests as the editor's GdUnit panel does ("The GdUnit panel", `gdunit-panel.md`).
