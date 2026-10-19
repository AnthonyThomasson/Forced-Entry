# Tests run through gdUnit4, and simulation tests stay GameTests

The game's tests are simulation tests: a `GameTest` (`tests/**/*_test.gd`) declares a world, runs it on the sim clock
and asserts what happened, and any engine error or warning logged meanwhile fails it. They used to run only through
the project's own runner (`scenes/testing/test_runner.gd` in a batch mode, `tools/run_tests.sh`, the in-game browser).
Issue #70 asked for gdUnit4, its editor panel and its command line, while the tests stay visible and playable in the
game.

Every test runs through gdUnit4 5.1.1 (`addons/gdUnit4/`), the last line that supports Godot 4.4. The simulation tests
are wrapped, not converted: one wrapper suite per domain and one per AI topic folder (`tests/<domain>/<domain>_suite.gd`,
`tests/ai/<topic>/<topic>_suite.gd`, extending `GameTestSuite`) lists its folder's tests from the catalog as the cases of
one parameterized test, one per test id, and plays each unchanged through the same `TestSession` the in-game runner
uses: its `configure`, `run`, sim-time timeout, checks and log gate decide the verdict, which the suite maps to gdUnit's
(FAIL and TIMEOUT failed; SKIPPED skipped; GAP skipped as "gap: expected to fail"; a gap test that passes failed).
`tools/run_tests.sh` drives gdUnit's command-line tool headless, with `--fixed-fps 60` and a log of its own per process,
and keeps its flags, lines, summary, `report.json` and bundles. The project's runner keeps only what a person watches:
the browser's Play and Run N checked, `--play`, `--queue` and `tools/play_tests.sh`. Native gdUnit suites
(`tests/<domain>/<name>_suite.gd`, extending `UnitSuite`) are allowed for pure logic only: they always supplement the
simulation tests, never replace them, and a behaviour is proved by a simulation test.

## Consequences

One verdict engine serves the editor's GdUnit panel (one case, one suite or everything, run or debugged, the world
framed in gdUnit's window) and the command line, and each run also writes gdUnit's JUnit and HTML reports. A new
`*_test.gd` shows up in gdUnit with no edit to any suite. Each process pays gdUnit's discovery of its suites (1.2 to
1.9 s; a one-test run went from 1.8 s to 3.2 s, a filter-word run over every suite from 11 s to 16 s). gdUnit's own log
scan is off (`report/godot/script_error`): it reads the project's log path, not the run's, so the log gate stays the
project's (`LogWatch`, `tools/scan_godot_log.py`), and gdUnit's log path is pointed at the run's own log in memory for
the run. gdUnit's console is kept in the run's `gdunit.txt` and left out of what a run prints. gdUnit minimises its
window, so the base suite restores it whenever a world is built. The coverage tool's probe finds the open test on the
running suite (the group `game_test_suites`). The addon is third-party code committed under `addons/`: the lint's
engine pass and gdstyle leave it out. gdUnit4-coverage stays out (`.out-of-scope/gdunit4-coverage.md`): it needs Godot
4.7 and gdUnit4 6.2.

## Considered options

- **Converting the GameTests to native gdUnit suites:** rejected. Hundreds of tests rewritten against gdUnit's asserts
  and scene runner would lose what a simulation test is: the declared world, the sim clock and its timeout, the event
  log and failure bundle, the log gate, GAP and the in-game browser that plays the same test a person watches. The
  prototype (`prototype/gdunit`) ran the same tests wrapped and converted, and wrapped ones passed unchanged.
- **Keeping the project's own runner:** no editor panel, no JUnit or HTML report, and the issue asked for gdUnit4. It
  starts faster (no discovery), which is the one thing given up.
- **gdUnit4 6.x:** needs Godot 4.5 or later; the engine upgrade is its own change (the follow-up for Godot 4.7, gdUnit4
  6.2 and gdUnit4-coverage).
