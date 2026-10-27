---
name: domain-testing
description: Deep implementation detail for the Testing domain (scenes/testing/ + tests/) — game tests that declare a world (arena, hand-laid room layout or generated house), the actors and objects in it and which behaviours are on, run it, and assert what happened; plus the in-game test browser/runner, the gdUnit4 suites that the headless CLI runner (tools/run_tests.sh) and the editor's GdUnit panel run, and native pure-logic suites. Use when writing or debugging a test, adding a behaviour switch, running the suite, or editing scenes/testing/. Any engine error/warning during a test fails it. Complements the `architecture` skill (interface 13; the world is lit through interface 20).
---

# Testing domain (`scenes/testing/`, cases in `tests/`)

A second composition root beside `main.gd`. It builds a test's world **only through the published
interfaces** (WorldGen + its catalogue lookups, the Objects factories, the character scenes and controller
contract, EventBus and character signals) and never reaches into domain internals. Its world stage, its NPCs' binding, a declared
match or declared squads and the overlay routing go through the composition root's match builder (`MatchBuilder`, architecture
interface 23), the module Main builds its matches with, so a test world is staged, bound and populated as Main's match is.

## Running tests

- **Lint first:** every `tools/run_tests.sh` run starts with `tools/lint.sh` (about 14 s for the whole tree, nearly all of
  it the engine pass; skipped for `--list`,
  `--self-test`, with `--no-lint`, and when the sources are the ones the last clean lint saw: the wrapper
  keeps a fingerprint of HEAD plus every uncommitted change in `$TMPDIR`, so a rerun of an unchanged tree does not
  lint again, while any edit, new file or commit does). It loads every project script with the engine's debugger on, the only
  way a headless run reports GDScript analyzer warnings (unused variable or parameter, integer division, a name that
  shadows a member or built-in, a redundant `await` ...), and prints them per file; any warning ends the run with exit 1
  before a test starts. The engine names no line, so the report gives candidate lines, and the exact `line:col` of each
  integer division (it recompiles the script once per `/`). Then the project lint rules (`tools/lint_rules/`) and
  gdstyle (`tools/gdstyle.sh`, pinned v0.4.0; config `gdstyle.toml`): `gdstyle fmt --check` names every script the
  formatter would change, `gdstyle check` every finding of its rules (a line over 100 columns, tabs, member order,
  naming, ...: all errors but some `quality/*` ones, 18 on, among them the three structural ones,
  `max-file-length`, `max-class-variables` and `max-public-methods`, and five off by decision, as `gdstyle.toml`
  says); one finding fails the run like a warning. Run `tools/lint.sh scenes/x.gd`
  for one script and `tools/gdstyle.sh fmt scenes/x.gd` to format it. Fix the code: never silence a warning or a
  finding (see `audit`).
- **CLI:** `tools/run_tests.sh [filter words] [--include-von]` runs every test through gdUnit4's command-line tool:
  `godot --headless --fixed-fps 60 --log-file <dir>/godot.log -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd … -a <suites>
  -- --out=<dir> <the run's options>`. The suites are the wrapper suites (`tests/<domain>/<domain>_suite.gd`, one per AI
  topic folder `tests/ai/<topic>/<topic>_suite.gd`: 27, each running its folder's catalog tests as one case per test
  id) and the native unit suites (`*_suite.gd` extending `UnitSuite`); the options after `--` reach them
  (`test_batch.gd`), which pick the tests. gdUnit's own console goes to `<dir>/gdunit.txt`, not to the screen. A fresh
  checkout (no `.godot/` class cache) is imported first, since without it every script fails to parse. It prints one
  line per test (`PASS/FAIL/TIMEOUT/SKIPPED/GAP  <id>  (<sim s> sim, <ms> ms)`, failed checks indented with ✗), then a
  summary, and writes `report.json`; gdUnit's JUnit `results.xml` and HTML report land in `<dir>/gdunit/report_1/`.
  In gdUnit's terms FAIL and TIMEOUT are failures, SKIPPED and GAP are skipped (a GAP with the reason "gap: expected to
  fail" and its failed checks). Exit code 1 means a test failed or timed out, or an
  error/warning was logged outside any test. **GAP** is a test tagged `gap` (a behaviour written into a spec that the
  code does not show yet, left red on purpose) that failed or timed out: expected, printed with its failed checks and a
  bundle like a FAIL, counted apart in the summary and never a failure of the run; a `gap` test that *passes* is a FAIL
  ("drop the gap tag"). `tools/run_tests.sh gap` lists them (tag prefix); `--failed` and `--fail-fast` leave them out. Filter words are word prefixes over id, name, domain,
  description and tags (`ai` matches the ai domain, not "chair"). Sandboxes live apart in `sandboxes/` and are never run.
  `requires_von` tests are skipped unless `--include-von` is passed (`--require-von` runs them and
  fails when no server is live), and are then paced in real time
  (see below). Run with the Bash sandbox disabled, like every Godot launch.
- **Per-run output dir:** the wrapper gives every process a fresh `mktemp -d`, passed as
  `--log-file <dir>/godot.log` (engine flag) plus `--out=<dir>`. The report, failure bundles, shots, gdUnit's
  reports (`gdunit/`) and its console (`gdunit.txt`) go under `<dir>` (`Report:` / `bundle:` lines print the paths) and
  the run's `LogWatch` follows `<dir>/godot.log` (`--log-file` is consumed by the engine, so it does not change the
  project setting: `test_batch.gd` derives the log from `--out`, and points gdUnit's own log path at it in memory for
  the run). So concurrent runs, and a game being played meanwhile, never share a log (a new process rotates the old
  `user://logs/godot.log`, and `LogWatch` tails by path) or overwrite each other's report. A run without `--out` (the
  editor's GdUnit panel) writes no `report.json` and keeps its failure bundles in `user://test_failures/`. `--report=FILE` also writes the
  run's merged report (results, stray logs) to FILE.
- **Quiet by default:** the game's own log of what happens (shots, punches, house seed, Von decisions, the
  `PERF …` numbers) goes through `GameLog.say` (General), which a `run_tests.sh` run turns off; pass `--verbose` to
  see it (e.g. to read the `PERF` lines when re-baselining). Engine errors/warnings are never gated.
- **Selecting:** `--domain=NAME[,NAME]` (exact domain(s); the filter words are word prefixes, so `ai` also
  catches a test that mentions "aim"), `--id=ID[,ID]` (exact ids), `--failed` (wrapper only: the tests
  that FAILED / TIMED OUT in the previous run of this checkout, read from its merged report in `$TMPDIR`),
  `--list [words]` (id, von flag, tags; runs nothing; `scenes/testing/test_list.gd`). `--id`, `--domain` and
  `--skip-domain` given more than once add up, as one comma list (`--id=a --id=b` is `--id=a,b`), in the wrapper, the
  suites and `--list`. A run whose selection holds no test at all (catalog or native, every shard together) ends on
  `no test matched the selection: <args>` and exits 1; a `--list` that lists none, and a `--changed` with nothing
  mapped (`No changed file maps to any tests`) or mapped only to domains `--skip-domain` leaves out (`No test to run:
  the changed files map only to skipped domains (perf).`), exit 0. `--failed` when the last report holds no FAIL /
  TIMEOUT prints `no failed test in the last report: nothing to rerun` and exits 0, and over a report it cannot read
  exits 2. Domain/id selection is decided from the file path, so unselected test scripts are never loaded. A native
  suite runs whole or not at all: its id is its path under `tests/` (`general/weighted_pick_suite`), a case's
  `<suite id>::<function>`; `--domain`, `--skip-domain`, an `--id` naming the suite or one of its cases and filter
  words on its path and name select it, `--self-test` never.
- **Speed:** `--jobs=N|auto` (wrapper only) splits the run over N parallel godot processes via each one's
  `--shard=I/N`, merges their output into one combined total, one `Slowest:` list and one `--failed` report.
  `auto` = cores, at most 6 (the stress tests stay under half their budgets at 6 jobs on a 12-core machine). **Without `--jobs`, a run of the whole suite uses `auto` and any selection (filter
  words, `--id`, `--domain`, `--failed`, `--repeat`) one process**, since a process costs about 3 s to start (gdUnit's
  discovery of its suites is 1.2 to 1.9 s of it), and filter words, which load every test script to match it, about 10 s
  more; an explicit
  `--jobs` never starts more processes than the `--id` list has ids. Not used with `--list`/`--self-test`/`--shots`
  (the `_a`/`_b` restore pairs need one process in id order). **Shards are balanced by measured cost:** the wrapper
  keeps each test's wall-clock ms (the mean of the previous and the latest measurement) in
  `$TMPDIR/example_godot_costs_<checkout hash>.json`, rewritten only after all shards have finished, and passes it to
  every shard as `--costs=<file>`; costliest tests go first onto the lightest shard (Von tests all stay in shard 0 and
  weigh it only when they run, and the native suites run only in shard 0). With no costs file (a fresh checkout) it falls back to the declared `timeout`, an
  unmeasured id costs the median. Perf tests budget wall-clock ms about 4x their baseline, so heavy CPU contention is
  the thing to suspect if one trips only under `--jobs`. `--fail-fast` stops after the first FAIL/TIMEOUT (per shard).
- **Output:** `--summary` prints only non-passing tests and the totals; every run reports wall-clock ms
  per test (`wall_ms` in the report) and ends with a `Slowest:` line. `--verbose`, `--json` apply too.
- **Other flags:** `--skip-domain=a,b` (leave those exact domains out; wins over every other selection, `--changed`'s included),
  `--repeat=N` (each test N times; names `FLAKY` / `FAILING` ones; a native suite, which runs once a process, runs
  again in N-1 processes of its own, and the tally and totals are every process's together; with a `--shard` given by
  hand it runs once: `NOTE native suites ran once (--shard)`), `--seed=N` (every
  `house()` uses that seed), and, in the wrapper only, `--changed` (see below), `--report=FILE` and `--strict-exit`.
  Options take the `--name=value` form. Any other `--` argument (a typo such as `--domian=ai`, or two flags quoted
  into one argument) exits 2 with `unknown flag: <arg>` and the header's usage lines: the wrapper forwards only the
  flags in its `BATCH_FLAGS` list, and `tools/tests/test_run_tests_flags.py` checks that every flag the batch reads
  is there (or in `WRAPPER_FLAGS`, the ones the wrapper gives the batch itself).
- **`--changed`:** the wrapper maps each changed file (`git diff HEAD` plus untracked) to a domain and
  runs those domains plus the ones that compose them (its `affected()` table, from the architecture
  dependency graph) in **one** process; `main.gd`, root scenes, `project.godot`, worldgen, art, general, audio, lighting and testing
  run everything, and `scenes/testing/` / the Von stub add `--self-test`. **An edited test file
  (`tests/<domain>/[<topic>/]<name>_test.gd`) runs only that test** (`--id=<domain>/[<topic>/]<name>`; it can only change its own
  result), unless its domain is already running; `tests/_ai`, `tests/_audio` and `tests/_lighting` helpers run that domain,
  `tests/_vehicle` runs `vehicle`, `audio` and `general` (its users), `tests/_perf` runs the `perf` domain, `tests/_harness` the self-tests, and an unknown helper folder everything
  (`tests/_main`, the Main-driving tests' helper, `tests/_outfit`, `tests/_objects` (`collider_probe.gd`, `Colliders.same_pieces`), `tests/_character`
  (`kill_probe.gd`, `Kill.kill_targets(t, count)`; `arm_probe.gd`, `Arms.check(t, c, when)`: both arms keep their length) and `tests/_navigation` (`bake_probe.gd`,
  `Bake.problem(region)`: what the NavigationServer would refuse in a baked polygon) are unknown to the mapping, so a change to any of them runs the whole suite).
  An edited `tests/<domain>/…_suite.gd` (a wrapper or a native suite) runs that domain.
  `GAME_TEST_CHANGED_FILES` (newline-separated paths) stands in for git's view of the changes, which is how
  `tools/test_log_gate.py` tests this mapping. **`--changed --staged`** (the pre-commit hook's) maps what is staged
  (`git diff --cached`) instead, and lints what the commit holds through `tools/lint_staged.sh` (the helper the hook's
  own lint runs too): the staged scripts (added, copied, modified or renamed, as they are on disk; the whole tree when
  `project.godot`, a gdstyle file or a file of the lint itself is staged: `tools/lint.sh`, `lint_report.py`,
  `lint_scripts.gd` / `.tscn`, the code of `tools/lint_rules/` but its tests; no lint when no script is), labelling a finding in a script not staged
  `not in this commit: <path>` (`tools/lint_label.py`); that lint never records the clean-lint fingerprint.
  `test_log_gate.py`'s `StagedChangedTests` run it through git in a throwaway repo.
- **Which command?**

  | Situation | Command |
  |---|---|
  | One test | `tools/run_tests.sh --id=<domain>/<name>` |
  | Just saw failures, fixed something | `tools/run_tests.sh --failed` |
  | Finished an edit | `tools/run_tests.sh --changed --summary` |
  | Before committing / big change | `tools/run_tests.sh --summary` (the whole suite shards over `auto` jobs by default) |
  | Intermittent | `--id=<id> --repeat=10` (`--seed=N` pins the layout) |
  | What exists? | `tools/run_tests.sh --list [words]` |
  | Edited `scenes/testing/` | `tools/run_tests.sh --self-test` (`--changed` adds it) |
  | Show a person the change's tests in a window | `tools/play_tests.sh` (or `tools/play_tests.sh <id> …`) |
  | Run or debug a case in the editor | the GdUnit panel (below) |

- **`--self-test`:** runs the harness's own tests (`tests/_harness/`, `internal: true` in `describe()`;
  hidden from the browser and normal runs) through their own gdUnit suite, `tests/_harness/harness_suite.gd`, which
  only `--self-test` passes to gdUnit: verdict rules, catalog selection and shard partitioning, LogWatch really seeing
  engine logs, the statics / Von-stub restore pairs (`*_a` then `*_b`, run in id order), and the probes
  `tools/test_log_gate.py` drives through environment variables (`verdict_probe`, `gap_probe`, `von_probe`,
  `warning_hold_probe`, `log_gate_probe`). Run it after editing `scenes/testing/`. `--changed` does this
  automatically when `scenes/testing/` changed.
- **`--shots`:** `tools/run_tests.sh --shots words` runs windowed (not headless) and saves
  `<bundle dir>/<id>__fail.png` for each failed test (printed as `shot:`); `t.bundle.screenshot(label)` saves one
  on demand (returns "" when headless or `--shots` is off). Read the PNG to see what went wrong.
- **`--windowed`:** `tools/run_tests.sh --windowed [words]` runs gdUnit in a window with vsync off (`--disable-vsync`), always in one
  process (no shard competes with what it measures, and one window), headless staying the default. A perf test's frame times then
  include the render, without being held to the display's refresh; the draw tests that compare pixels
  (`general/fill_batch_matches_draw_calls`, `items/prepaint_covers_the_draws`) run their image checks only this way.
- **Coverage:** `python3 tools/test_coverage.py` lists untested domains (a domain's tests counted in `tests/<domain>/**/*_test.gd`, its
  topic folders included), unused switches and interfaces no test calls.
- **Failures:** a FAIL/TIMEOUT prints each actor's final state and the `t.trace` series ranges, and writes
  `<out dir>/failures/<id>.json` (path printed as `bundle:`) with the full time-stamped event log, the
  final snapshot (actors, objects, and vehicles with their position, rotation and speed), traces and logged errors. See the `test-debug` skill.
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
  Held keys are polled state and cannot be told apart. The three `tests/general/camera_*_test.gd` use it; the
  browser's details pane lists "Locked while it runs".

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

## Writing a test

**A behaviour is proved by a simulation test** (a `GameTest`: a declared world, run and asserted on, below).
Native gdUnit suites are for pure logic only and always supplement the simulation tests, never replace them: a native
suite may add fast checks of a pure function beneath the simulation test that proves the behaviour (see "Native unit
suites" below).

**No tautological tests.** A test exists to fail when the behaviour is wrong, so every assertion must be one the
code could get wrong:
- Expected values come from the spec (`docs/`, the ticket, the interface's description) or from what a player would
  see, never worked out the way the code does: no calling the function under test (or a helper it shares) to compute
  the expectation, no copying its formula, no reading its tuning constant back as the expected value (a probe keeps
  its own copy of the spec's numbers, as `door_view_probe.gd` does).
- It asserts an outcome the world shows (the shot landed, the health dropped, the NPC went in by the doorway), not
  that the code did what the test told it: a setter read back, a `von_script` pick reported as picked, a stub's answer
  echoed, a constant equal to itself, a node the test itself added found in the tree.
- A premise the asserts rest on is checked on its own, as a premise, and never counts as the test's proof.
- The check before keeping it: break the behaviour it covers (invert the condition, drop the call, zero the effect)
  and it must go red. A test that would still pass is rewritten or deleted, not kept for coverage.

One file `tests/<domain>/<name>_test.gd` that `extends GameTest`. Id = `<domain>/<name>`. A domain with many tests
splits them one folder deeper by topic (`tests/ai/entry/`, `flank/`, `gaze/`, `posture/`, `investigate/`, `combat/`,
`movement/`, `decision/`, `perception/`, `stack/`, `grenade/`, `debug/`: the overlays): the id is then `<domain>/<topic>/<name>`, the domain is still the first
folder (so `--domain=ai` and `--changed` see it), the descriptor's `category` is the topic and the browser shows a
row per topic under the domain. The file name keeps its topic prefix (`entry_waits_for_stack_test.gd`), the name
the specs quote.

**Sandboxes** (worlds you play by hand) are separate: `sandboxes/<name>_sandbox.gd`, same `GameTest` base, no assertions or timeout. `TestCatalog.discover_sandboxes()` lists them for their own browser section; `discover()` and the gdUnit suites never see them (`--play <words>` can still open one). They are `player_gun_range_sandbox.gd` ("Gun range": the player with every gun, 3 stun (7) and 3 frag (8) grenades re-armed through
`Character.inventory.set_loadout` 2 s after the last of its grenades goes off, which restocks the guns too (its `Restock` node), a dummy crouched behind a
couch to show cover (`CoverSpot`), and the armour range of nine dressed dummies to the south) and `vehicle_sandbox.gd` ("Vehicle yard": a walled concrete yard with the player, a car and a van, furniture to shove and three dummies; `nav.rebake` off, since rammed furniture would re-bake as overlapping holes). `sandboxes/showroom/` holds a ticket's temporary showroom (`ticket-assets`), deleted before its audit.

```gdscript
extends GameTest

func describe() -> Dictionary:
	return { "name": "Pistol shot wounds a target", "tags": ["pistol"], "timeout": 6.0 }

func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(600, 250))

func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit"), 2.0), "the shot lands"):
		return
	t.check(t.actor(&"target").health < 50.0, "the target lost health")
```

- **`describe()`** (all optional): `name`, `domain`, `description`, `tags` (the tag `gap` marks a test written
  before the behaviour exists: it is expected to fail and reports GAP, see "Running tests"), `timeout` (sim s, default
  10), `requires_von`,
  `fail_on_errors` / `fail_on_warnings` (default true), `allowed_logs` (regexes).
- **`configure(s: TestSetup)`** is data only, and the browser also calls it to list the switches.
  - World: `layout(rooms, doors, { thickness })` (a hand-laid building: `rooms` = `[{ key, type, rect,
    floor? }]`, `doors` = `[{ pos, width }]` on the walls the rooms share or on an outer edge; walls in the
    house style, doorways open, so the nav bake and `WorldGen.get_rooms` / `get_openings` work as for a
    house), `arena(rect, { floor, walls, thickness })` (a walled room in the house style, with the same
    `rooms` meta a house has) or `house(seed, plan := "", entrance := Vector2.ZERO)`. Default is an
    800×500 arena.
  - Objects: `object(id, catalogue_key_or_definition, pos, opts)`. Objects are placed under the
    house/arena root before the nav bake, so they are carved.
  - Vehicles: `vehicle(id, kind, pos, rotation := 0.0, props := {})` (`kind` `car` / `van`: `res://scenes/vehicle/<kind>.tscn`;
    rotation 0 = its front toward +x). Placed under the world root after the nav bake (not carved: the AI ignores vehicles), in
    place before they join the tree; a kind with no scene places nothing and `t.vehicle(id)` is then null. The world then waits
    one physics frame before the actors, because a new body joins the physics space only at the next step.
  - Actors: `actor(id, kind, pos, props)`. Kind is `puppet` (scripted), `player` (human-driven),
    `defender`, `invader`, or a scene path. `props` are set on the character before `_ready` (a `component:prop` key on that component of it, through
    `set_indexed`: `"anatomy:pose:gait:_stride"`, `tests/general/test_world_component_prop`; for example `max_health`, `start_slot`: 1 unarmed / 2 fists / 3 pistol / 4 key / 5 SMG / 6 assault rifle, `faction`, `movement:speed` and `movement:aim_point`, and the ammo props
    `inventory:start_rounds` (what the starting gun is loaded with; -1 = full) and `ammo:spare_magazine_types` (e.g. `[]` for none,
    `[&"extended"]`; the default is two standard magazines for each gun, so a test counting spares sets it)). Actors built here
    keep `default_inventory()` (every item) and the weapon they ask for: only a match (Main's, or a setup's `declared_match`) arms a spawn
    with its side's loadout (`MatchBuilder.arm`, `Character.inventory.set_loadout`). To retune a gun for one test, `set_static(GunConfig, "guns", modified_copy)` (e.g. spread 0 for a
    straight shot). Use
    `set_props(id, "GoalController", {...})` for a child's exports, a key an indexed path for an NPC's tunables
    (`{ "tuning:entry:enabled": true }`, interface 7) (the look is the `Wardrobe` child's: `set_props(id, "Wardrobe", { "rank": 2 })`,
    `look_seed`, `style`). An NPC actor is bound by the match's own rule before it joins
    the tree (`MatchBuilder.bind_npc`): the house's `rooms` and `openings`, and for an invader the front entrance as its
    `entry_point` (`MatchBuilder.entry_point_for`; none in a world with no front entrance, none for a defender).
  - Squads: `squads(opts := {})` builds one squad per faction over the setup's actors of that faction, in declaration order, as a
    match builds its own (`MatchBuilder.squads_over`, the squad tail `populate` ends with, after the actors spawn: the leader by rank, then
    declaration order, each member handed its squad), and the squad-leaders overlay over them, shown as the setup's overlays say. `opts.human` names an actor that
    leads its faction's squad as the human does: it is handed its stack radio (`MatchBuilder.bind_player`) and its squad through it,
    `own_claims` on the invaders' side only. `opts.claim_ttl` is how long (s) each squad keeps its members' entry claims (the `SquadsSpec`'s
    `claim_ttl` it hands `squads_over`): by default its NPCs' `tuning.radio.callout_ttl` (`MatchBuilder.callout_ttl_of`), which is 0 over puppets alone, so a squad of
    puppets keeps no claim unless `claim_ttl` names one: the two that radio claims name the NPCs' 6 s
    (`general/squad_go_latched_off_claims`, `ai/stack/stack_player_go_after_funnel_brush`). A world
    that declares no squads has none: its NPCs pick their own goals.
  - A whole match: `declared_match(overrides := {})` populates one over the staged world as Main does (`MatchBuilder.populate`, after the
    actors): `overrides` are `MatchBuilder.spec`'s (each side's `count`, `loadout` and `at`, `human`, `spawn_clearance`,
    `invader_margin`, ...), the world's seed its `seed` unless they name one, the setup's overlays its `overlays`. Its `human` may
    name an actor (`{ actor, side, lead, at }`, `actor` in place of `node`): that actor is joined to its side, armed and handed its
    stack radio. The match's NPCs are not test actors: read them off `t.world.match_handle`. Declare `squads` or `declared_match`, not both (an error).
  - Behaviour: `switch(name, on)` (table below) and `set_static(ConfigClass, prop, value)`. A `prop` the holder has no
    static var by (a switch row's too) is an error that fails the test (`TestWorld._set_static`), never a silent no-op.
  - Scripted Von: `von_script([{ pick: id, question: substring? }, …])` replaces the server with those
    picks (first rule whose id is offered; else the first offered option), so an AI test needs no server
    and is deterministic (`von_script(rules, latency_frames)` holds each answer back that many physics frames, `DecisionStub.latency_frames`, to test what an NPC does while a decision is in flight); `von_down()` makes every decision fail (the hold-steady fallback). Read what was
    asked off `DecisionStub.requests` (`{ state, question, options, pick }`, the AI decision sub-domain's stub). Ids are the decision tree's node
    ids (`combat`, `flank`, `engage`, …) and option ids. Keep `requires_von` tests for judging Von itself.
  - Presentation: `show_overlays(["show_vision", …])` and `camera_follow([ids])` (default frames all
    actors; the camera's hand-pan is off when a `player` actor is present, since WASD walks it).
    `lock_interaction([&"camera", …])` switches off user interactions in a headed run (see below).
- **`run(t: TestContext)`**, a coroutine. Always wait through `t`. A raw `await get_tree()…` can
  resume into a torn-down world.
  - Waits, all in sim time: `await t.seconds(s)`, `await t.frames(n)`,
    `await t.until(cond, timeout, msg := "") -> bool` (with `msg`, a timeout records a failed check).
  - Lookup: `t.actor(id)`, `t.puppet(id)` (the ScriptedController), `t.object(id)`, `t.vehicle(id)`,
    `t.controller(id, method)` (e.g. `&"current_act"` for an NPC brain; `TestContext.controller_of(character, method := &"control")`
    is the same for a character that is not a test actor, e.g. a match's NPC), `t.world`, `t.rooms`, `t.time`; off the world (a `TestWorld`, typed `Node2D` on the
    context, so a `var` takes an explicit type): `t.world.match_handle` (the declared match's handle, `{ world, house, rooms, openings,
    nav_region, nav_debug, combatants, squads, player_stack, leader_overlay }`, {} with none), `t.world.squad(faction)` (the declared squad
    of that faction, `squads`' or the match's, null with none) and `t.world.player_stack` (the human leader's stack radio, null with none).
  - Event log: `t.events_of(topic, filter)`, `t.happened(topic, filter)`, `t.spawned(name_part)`.
    Topics are every EventBus topic (`&"hit"`: position, victim, attacker, direction, damage;
    `&"callout"`), `&"died"` / `&"hit_landed"` per actor (`actor` = its id; hit_landed adds body,
    damage, hand, −1 = shot), and `&"spawned"` / `&"removed"` for direct children of the world root
    (blood splatters and pools, debris, projectiles, dropped items).
  - `t.trace(name, value)` samples a number over time (a distance, a health) for the failure output.
  - Assertions: `check(cond, msg)` (soft), `require(cond, msg)` (ends the test; follow it with
    `if not …: return`), `expect_eq`, `expect_near`, `skip(why)`, and on its `verdict` part
    `t.verdict.expect_log(pattern, count)`. A test that asserts nothing fails.
- Puppet (`scripted_controller.gd`): `aim_at(node_or_point)`, `walk_to(point)` + `has_arrived()`
  (straight line, no pathing), `walk(dir)`, `set_run(on)` (holds run while moving), `set_posture(p)` (wants `stand` / `crouch`, written every frame like the AI does; `&""` stops asking), `toggle_crouch()` (one press of C), `stop()`, `select_slot(n)`, `punch()`, `kick()` (the leg kick), `shoot()` (one click), `hold_fire(on)` (hold the trigger: an automatic gun fires at its rate; a semi-auto one is unaffected), `reload()`,
  `interact(object, id)` (refusals land in `failed_interactions`), `end_interaction()`, `use_vehicle()` (one press of E: get in
  by the nearest usable door, or out; ignored by a character without a `use`) and `drive(throttle, steer, handbrake)` (holds the
  driving keys as the player's do: `movement.move_input` = `(steer, -throttle)` limited to length 1, `movement.run_input` = handbrake; `drive(0, 0, false)`
  lets go). Actions run on
  the character's next frame, and the character derives `facing` from the aim one frame later, so
  aim, wait a moment, then fire.
- Make randomness deterministic where the assertion depends on it (e.g. `projectile.flyover` off,
  since a character is partial cover).

### Native unit suites (pure logic only)

They supplement the simulation tests, never replace them: write the `GameTest` that proves the behaviour first, then,
if a pure function beneath it (no world, no nodes, no frames) earns fast edge-case checks, a native suite for it. One
file `tests/<domain>/<name>_suite.gd` that `extends UnitSuite` (`scenes/testing/unit_suite.gd`, a `GdUnitTestSuite`),
with `test_*` functions using gdUnit's own asserts (`assert_that`, `assert_int`, `assert_float`, ...;
`override_failure_message` says what broke). The example is `tests/general/weighted_pick_suite.gd`, General's
`WeightedPick`:

```gdscript
extends UnitSuite
## Native unit suite (pure logic) for General's `WeightedPick`, architecture interface 11: ...


func test_the_keys_take_their_stretches_in_their_order() -> void:
	_premise_zero_roll()
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 })).is_equal("b")
	assert_that(WeightedPick.key(_zero_roll(), { "b": 1.0, "a": 1.0 }, true)).is_equal("b")
```

- No tautologies (above): its expected values come from the spec (the interface's description), never worked out the
  way the code does; a premise the asserts rest on (here, that an rng at state 0 rolls 0.0) is checked on its own first.
- The log gate holds: an engine error or warning logged during one of its tests fails that test.
- `run_tests.sh` runs it in shard 0, ids `<path under tests/>::<function>` (`general/weighted_pick_suite::test_…`);
  `--changed` runs its domain when it or the domain's code changes; the GdUnit panel lists it like any suite.
- Name it `*_suite.gd`, never `*_test.gd` (that is the catalog's), and keep it out of the helper folders (`tests/_*`).

## Performance tests (domain `perf`, `tests/perf/`)

Their own category: regression guards for speed and runaway object counts, one folder, one browser section, one
selector. They are ordinary tests that load other domains, so they live apart from them:

| Test | Load |
|---|---|
| `perf/match_5v5_stress` | the whole-match case, built as Main builds one (`s.declared_match({ defenders: { count }, invaders: { count } })` over `s.house(Perf.MATCH_SEED, Perf.MATCH_PLAN)`, through `MatchBuilder.populate`: `Perf.configure_match`): a generated house pinned to the largest plan, `garage_home` (so a catalogue change never shrinks the house it fights in), five defenders at clear spots in random rooms and five invaders in one group beside the front door, each side with its spec loadout (the invaders' helmet, plate carrier and steel plates front and back, a stun and a frag each; the defenders' plain clothes; a random gun each), styled and ranked, one squad per side, every debug overlay off (the spec's `overlays` default), nav re-baker, blood, debris, sound and radio on, scripted Von; the sides in contact before the window opens (`Perf.await_contact`, a premise) |
| `perf/match_10v10_stress` | the same with ten a side: the largest match the game means to carry, held to the same standard. Each squad's members but its leader follow it (every member but the leader following is a premise), so the squads' cost (the trail, the follow spots, the `follow` primitive, the leash) is in the frame, and the sides are in contact as the window opens, so it measures the teams' fight; it logs when contact came (`PERF 10v10 match contact at <s> s`), the window (`PERF 10v10 match window: <n> knowing a hostile as it opened, <n> shots in it`) and the follow count (`PERF 10v10 match node growth ..., <n> following at the end`). **Red on a quiet machine** (its p95 and max), by the user's decision: an invader's decision that weighs its grenades (the throw spots and the escape from the burst, in its decision snapshot) spikes in one frame; the standard is untouched and the fix is #98 |
| `perf/npc_crowd_stress` | twelve scripted-Von NPCs sensing, deciding and shooting in one open furnished arena (everyone sees everyone: the decision snapshot's worst case) |
| `perf/automatic_fire_stress` | SMGs and rifles on the trigger plus pistols clicking into furniture: one run covers the single-shot and the automatic path |
| `perf/hit_overload_stress` | hundreds of hits on one chair and one character: deformation, debris, blood and their caps |
| `perf/crowd_deaths_stress` | a whole 5v5 (ten characters) killed in one frame: ragdolls, blood, bleed-out |
| `perf/furniture_pile_stress` | 120 rigid bodies shoved at once |
| `perf/bake_and_path_stress`, `perf/generate_houses_stress`, `perf/audio_bank_render` | one-shot work: nav re-bake and path queries, world-gen, the whole sound library rendered from a cold cache |
| `perf/grenade_match_stress` | P1 of `docs/grenades.md`: the 5v5 of `match_5v5_stress`, and once the sides are in contact a puppet on the invaders' side (a test actor, not one of the match's, carrying the three of each P1 names) throws three frags and three stuns among the fighters over about 3 s (through the controller contract); measured from the first throw to 3 s after the last burst. The match's invaders carry grenades of their own, so its premise (all six went off) and its among-the-fighters check count only the puppet's: its blasts by `attacker`, its stuns by the frames its own stun bursts went off in |
| `perf/grenade_burst_stress` | P2: a frag and a stun going off together among twelve pieces of furniture and eight characters in an arena (blood, debris, hit particles and sound on, `nav.rebake` off); the burst frame and the 2 s after it |

Twelve guards in all. `tools/run_tests.sh --domain=perf` (or the word `perf`) runs just them; `match_10v10_stress` is red on a
quiet machine until #98. The pre-commit hook leaves them out (`--skip-domain=perf`): their frame-time budgets fail when the
machine is busy, so run them on their own before a push that touches a per-frame path. They stay in the default run, balanced
across shards by measured cost like every test, and `--changed` adds the domain whenever a scene they exercise changes
(`affected()` in `tools/run_tests.sh`) or `tests/_perf/` changes. The shared helper is `tests/_perf/perf_probe.gd` (`const Perf :=
preload(...)`; not a test), with the match guards' contact: `await_contact(t, label, characters, limit_s)` runs a guard's warm-up
on until a shot has been fired and some NPC among `characters` knows a hostile at once (at most `limit_s` s more), logs `PERF
<label> contact at <s> s` and returns whether contact came (the guard `require`s it), and `knows_hostile(c)` (an NPC knowing a
hostile now, `known_contacts_for_display()`; false for a dead or freed one). The three match guards share one match and one warm-up:
`configure_match(s, per_side)` declares it (the house `MATCH_SEED` on `MATCH_PLAN`, `s.declared_match` with `per_side` a side, scripted Von, the
callouts, vision and pursuit on), `warm_until_contact(t, label, characters)` runs `MATCH_WARMUP_S` (6 s) and then `await_contact` (at most
`MATCH_CONTACT_WITHIN`, 20 s) and `require`s it as the premise, and `MATCH_LOGS` is their `allowed_logs` (the re-bake's nav lines). `character/standing_body_repaints_on_change` keeps a count but is
a functional test of its domain. A wall-clock budget belongs here and nowhere else: the lint rule `timing_in_perf`
fails a `Time.get_ticks_usec()` under `tests/` outside `tests/perf/` and `tests/_perf/` (`Time.get_ticks_msec()`, a
real-time wait's clock, is left alone), so no budget runs in the pre-commit hook.

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` -> avg / p95 / max): the main-loop iteration the frame ran
  in, from its physics frame to the next iteration's first frame signal. Headless `--fixed-fps` outruns the clock and
  steps one physics frame an iteration, so that is frame-to-frame wall time, the CPU cost (rendering is not covered);
  in the GdUnit panel's run, paced to the clock, the waits between iterations are left out, so it measures the same. Also one-shot
  ms (`Perf.time_ms`) and exact counts (`Perf.nodes()`, `Despawner.count()`, dent / blood-pool caps).
- **Rendered too:** `tools/run_tests.sh --windowed --domain=perf` (or `--id=`) measures the same tests with the render in each frame.
  The two grenade tests frame the whole fight with the test camera (the runner's, or the gdUnit suite's), as a player's screen would show it, the camera locked (P1 points
  it at the match's ten with `frame(characters)`, P2 keeps the default framing of every actor), so every body is drawn; headless (a 64 px
  viewport) they size the root viewport to the project's window first, so the camera frames the same view either way. Windowed, General's `FillBatch` batches the plain-coloured shapes (off headless, which renders nothing).
  Their headless and windowed numbers, before and after issue #56, are in `docs/grenades.md`, Performance; windowed they do not all meet
  the standard yet, which is the honest state, not a reason to loosen it.
  **Windowed keeps the same budgets** (issue #78): no windowed exemption and no looser number; what a window costs is fixed at its cause,
  each fix pinned to the old pixels or bytes. The sound library's pre-warm, which synthesized on the main thread about 10 ms a frame for
  the first seconds of every windowed run (`automatic_fire_stress` 25.4 / 38.9 / 48.5 before), renders on a worker thread
  (`domain-audio`); a body's one-polygon parts (limb segments, shoulders, fists, head, a damaged body's darkened ones through
  `Deformation.darken`, the trunk's faces) and its standing shadow's plain black shapes are meshes the body keeps
  (`domain-character-body`, `body_meshes.gd`), not a polygon command each, pinned pixel for pixel by
  `character/body_mesh_matches_polygons` (windowed); a debris chunk draws its chips in pages of 32, so a chip landing or the oldest
  dropped repaints one page, not the ~1,450 chips `hit_overload` repainted a frame (3.7 ms of script windowed; `domain-physics`,
  `physics/debris_pages_match_one_batch` windowed); and a hit's spray no longer waits for its splats' merges (0.9 ms a frame), which
  finish later in the frame (`domain-physics-blood`). Measured and dropped: batching `draw_marks`' discs across marks (19 % of the
  painted pixels change where dents cluster), one body-sized bounds for every mesh (it could change which 15 lights a part keeps), the limb
  outlines as kept meshes (exact, but no faster: three A/B runs each, `grenade_match` 14.70 / 20.74 against 15.09 / 21.75 avg / p95,
  `npc_crowd` 12.01 / 21.83 against 11.56 / 19.68). The latest windowed record, from before issue #95 (the match guards then placed their own match, and a twelfth guard,
  `match_10v10_team`, measured the 10v10 with its squads): three windowed runs of the twelve perf tests on 21 October 2026
  (`tools/run_tests.sh --windowed`, each alone: no other Godot, the worktree's editor closed), this machine's quiet baseline that day
  a 1-minute load of about 5 (ordinary apps), the load sampled every 10 s through each run (its range in the header), and one headless
  run (avg / p95 / max ms; bold misses). Windowed run W2, started at 6.19, over the < 6 bar, is discarded:

  | Test | W1 (3.6-4.3) | W3 (4.3-5.6) | W4 (3.2-4.0) | Headless (2.9-3.0) | Panel (3.9-5.1) |
  |---|---|---|---|---|---|
  | `automatic_fire` (gunfire) | 13.17 / 17.12 / 19.74 | 14.44 / 18.71 / 21.55 | 14.90 / 19.64 / **42.56** | 5.39 / 7.70 / 11.50 | 13.38 / 18.50 / 24.79 |
  | `crowd_deaths` (crowd fall) | 10.87 / 16.53 / 21.83 | 12.40 / 18.57 / 23.86 | 11.67 / 18.24 / 31.64 | 8.04 / 11.77 / 17.32 | 11.92 / 17.04 / 20.38 |
  | `furniture_pile` (moving) | 1.83 / 5.60 / 5.90 | 8.48 / 10.18 / 17.17 | 6.94 / 12.83 / 18.55 | 0.73 / 2.08 / 2.86 | 3.93 / 7.61 / 24.35 |
  | `grenade_burst` (P2) | 8.94 / 11.80 / 27.85 | 9.39 / 12.64 / **34.84** | 10.29 / 12.52 / **36.40** | 6.45 / 8.28 / 22.77 | 10.49 / 13.08 / **40.50** |
  | `grenade_match` (P1) | 15.98 / **20.94** / **37.51** | 15.20 / **21.89** / 31.93 | 14.01 / **20.24** / 28.47 | 9.71 / 14.63 / 20.34 | 15.59 / **21.98** / 31.88 |
  | `hit_overload` | 11.93 / 13.96 / 15.15 | 11.67 / 13.42 / 14.64 | 12.77 / 14.81 / 16.32 | 7.86 / 9.60 / 10.38 | 12.03 / 14.94 / 17.74 |
  | `match_10v10` | 14.81 / **20.21** / 27.72 | 13.54 / 18.08 / 21.78 | 14.71 / 18.12 / 21.75 | 10.70 / 13.72 / 21.67 | 16.20 / **20.87** / 25.88 |
  | `match_10v10_team` | 11.16 / 13.37 / 17.44 | 12.09 / 15.49 / 21.32 | 11.49 / 13.84 / 31.61 | 9.49 / 13.52 / **38.69** | 12.35 / 15.21 / 17.69 |
  | `match_5v5` | 8.33 / 11.44 / 14.40 | 8.17 / 10.55 / 14.74 | 7.22 / 11.78 / 19.90 | 6.08 / 10.23 / 14.71 | 8.89 / 13.22 / 19.02 |
  | `npc_crowd` | 10.43 / 18.88 / 27.83 | 10.85 / 17.84 / 24.20 | 10.58 / 18.75 / 24.49 | 4.56 / 11.45 / 16.28 | 11.52 / 18.37 / 31.41 |
  | `bake_and_path`, `generate_houses` | pass | pass | pass | pass | pass |
  | **passed** | 10 of 12 | 10 of 12 | 9 of 12 | 11 of 12 | 9 of 12 |

  The panel column is one **Run overall** from the editor's GdUnit panel (all 588 cases, every suite, an hour; started at 22:57 at a
  load of 3.3, 2.4-6.0 through the run, the perf suite from 23:56 at 3.9-5.1; no other Godot but the editor and its runner; the
  numbers are the run's `PERF` lines in the project log): 584 passed, the harness's `gap_probe` skipped as a gap, and three perf
  tests failed, each on a measure the windowed CLI runs above miss too (P1's p95, `match_10v10`'s p95 at the margin, `grenade_burst`'s
  one-frame max), while every test that passes in all three windowed runs passes. So the panel gives the windowed CLI's perf
  verdicts: not green while P1 misses.
  `hit_overload`, which missed two windowed runs of three before the debris pages (16.3-17.2 / 19.2-20.9), passes every run.
  `match_10v10` misses its p95 at the margin even at a quiet load (20.21 in W1, at 3.6-4.3) and passes the other two. Headless,
  `match_10v10_team`'s one 38.69 frame was a one-off: `--id=perf/match_10v10_team_stress --repeat=3` alone passed 3 of 3; the other
  eleven pass. **What is left:** `grenade_match` (P1), which misses its p95 in every windowed run (20.24-21.89), and beside it the
  one-frame maxima over 33.4 ms in two of the three windowed runs (W3: `grenade_burst` 34.84; W4: gunfire 42.56 and `grenade_burst`
  36.40), besides P1's own 37.51 in W1. Of P1's windowed frame (14.0-16.0 ms on average above) about 10 ms is paid headless too (9.71
  above): the characters' physics frame with the AI it drives (6.4 ms, 0.41 ms a body in both modes, measured during #78 with a
  throwaway timer on every `_process`, `_physics_process` and `_draw`), the ragdolls, and the fallen bodies, which repaint every frame until
  they settle (about 2 ms a repaint, mostly the trunk's outline built twice, body and shadow; only 3-5 % of those repaints change
  nothing). The window adds the rest: the standing bodies' drawing on the script side (5.3 ms against 3.5 headless in that same timed
  run) and the engine's render of the frame. Closing it needs work on the AI and the fallen bodies, outside #78.
  **Since issue #95** the three match guards build a real match through `MatchBuilder` (the invaders with plates and grenades, styled
  and ranked, in squads, beside the front door), and `match_10v10_team` is folded into `match_10v10`. Re-baselined headless only
  (`--domain=perf --verbose --summary --no-lint`, three valid runs a side, each started at a load under 3.5 with no other headless
  Godot, a run whose load went over 4 discarded; old 4af0b43, new 91400e6's guard code, measured before the branch was rebased onto
  #81), medians, avg / p95 / max ms, bold misses:

  | Test | before #95 | since #95 | 7d067bf (after the review fixes) |
  |---|---|---|---|
  | `match_5v5` | 5.93 / 9.10 / 12.47 | 5.55 / 11.31 / 22.89 | 5.28 / 9.22 / 23.40 |
  | `match_10v10` | 10.88 / 14.69 / 22.42 | 11.74 / **22.04** / **65.34** | 12.11 / **25.91** / **51.13** |
  | `match_10v10_team` | 8.91 / 11.94 / 14.41 | (folded into `match_10v10`) | |
  | `grenade_match` (P1) | 10.16 / 15.09 / 24.20 | 10.58 / 17.29 / 33.18 | 10.80 / 17.14 / **35.51** |
  | `npc_crowd` | 4.49 / 10.04 / 16.44 | 4.48 / 10.62 / 16.70 | 4.66 / 12.07 / 16.83 |
  | `automatic_fire` | 5.40 / 8.24 / 10.96 | 5.52 / 8.60 / 10.47 | 5.07 / 7.80 / 10.81 |
  | `hit_overload` | 7.97 / 9.87 / 10.60 | 8.54 / 10.10 / 10.66 | 7.72 / 9.28 / 10.27 |
  | `crowd_deaths` | 7.49 / 11.80 / 16.12 | 7.48 / 11.87 / 15.72 | 7.76 / 11.72 / 16.77 |
  | `furniture_pile` (moving) | 0.72 / 2.15 / 2.61 | 0.72 / 2.14 / 2.65 | 0.71 / 2.09 / 2.47 |
  | `grenade_burst` (P2) | 6.41 / 8.47 / 22.10 | 6.89 / 8.90 / 22.50 | 6.82 / 8.39 / 22.37 |
  | `bake_and_path`, `generate_houses` | pass | pass | pass |

  The averages barely move; the tails do. The 5v5 and P1 medians pass, each grazing or missing its max in one run of three; the
  10v10's window holds 10 to 16 NPCs knowing a hostile and 21 to 48 shots (the team guard's held 2 and 0), and its p95 and max miss in
  every run: one invader's decision that weighs its grenades (`AgentTactics.throw_spot` about 5 ms a search, up to four a snapshot, and
  `AgentThrow.escape` 5 to 14 ms) takes 20 to 47 ms in one frame. With the invaders' grenades taken away its max fell within 33.4. The
  guard stays red and the standard untouched, by the user's decision; the fix is #98. Not yet re-measured windowed.
  The 7d067bf column re-measures the tree after the review fixes (the give-way's look-ahead cut to the walk left and the
  follower's catch-up run, on a per-frame path, and the three match guards on one `Perf` helper): `tools/run_tests.sh --domain=perf
  --verbose`, three runs back to back on 2026-10-24 (12:35 to 12:38), each started at a load under 4 (3.60-3.96, 3.62-4.22 and
  3.15-3.32 through the runs; none discarded), medians. Within the runs' spread: the 10v10 misses its p95 and max in every run (#98),
  P1 its max in two of three (25.30, 35.51, 50.28), the 5v5 its max in one of three (38.26), as before; every other guard held its
  budget in all three.
- **The standard:** a match runs without frame loss, so every frame-based test holds `Perf.SMOOTH_AVG_MS` (16.7, one 60 fps
  frame, the Performance overlay's target), `SMOOTH_P95_MS` (20) and `SMOOTH_MAX_MS` (33.4, two frames) through
  `Perf.within_frames(t, label, stats)` (which holds a `frame_stats` result to those three itself), at the scale of the largest match (twenty characters, `match_10v10_stress`), with no looser tail.
  One-shot work
  (`Perf.time_ms`) keeps a `const` budget at the top of its test, about 4x the baseline stated in the comment above it.
  `Perf.within` prints `PERF <label> <value> (budget <limit>)`, traces it, and fails the check with the value. Counts
  (nodes, dents, pools) are asserted tightly.
- **Re-baselining:** run `tools/run_tests.sh --domain=perf --repeat=5 --verbose` and read the `PERF` lines. The frame standard is not
  loosened to fit a slower game: make the game faster, or state in the test why one load is heavier than a match. Update the
  "before" numbers in a test's comment only when its load changes.
- **Finding what costs:** the wall time of a frame is script time, so attribute it by timing. A throwaway `Time.get_ticks_usec`
  accumulator wrapped around the suspect functions (never committed), dumped at the end of the measured window, ranks them
  in minutes; switching a feature off with `set_static`/`switch` shows what it is worth. Measure before reading: a per-frame
  cost is rarely where the code suggests.
- **Gotchas:** a lambda captures ints by value (count into an Array); `nav.rebake` is off in tests that
  shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync error; the nav
  test covers re-baking), and the 5v5 test, which keeps it on, allows that log (`allowed_logs`); world-gen's first run in a
  process is slower (cold caches), so its budget covers the cold case; headless runs skip the sound pre-warm, so a test that
  plays sound calls `Perf.warm_sounds()` first or turns `audio.sound` off, or the first play of each variant (9 to 35 ms) lands
  in its worst frame. A speed-up must not change what the game does: where a fast path replaces a plain algorithm, a test
  pins its output to the plain one (`navigation/furniture_union_fast_path`, `physics/blood_splat_merge_fast_path`,
  `physics/convex_pieces_match_plain_scan`, `physics/shape_polygon_cache`).

## Tactical entry tests (tag `entry`)

`tests/ai/entry/` pin down `docs/tactical-entry.md` (E1 to E15 here, E16 to E22 in the sections below; each header names its behaviour): staging and
the approach, the stack's slots, the pie, the crossing, the corners, the ready barrier and the radio, the solo entry
and a joining ally, clearing, covering the doorways on and rear security. Scripted-Von tests on the Terrace house (`Maps.house(s, false)`, bare
rooms so the geometry is clean), through `tests/_ai/entry_probe.gd` (`const Entry := preload(...)`): `rules(s, door)`
(SEARCH > ENTER > that doorway, engage in a fight), `npc` (an invader that walks; a `tuning:decision:decide_interval` in its `gc` offsets its decide timer),
`target`, `guard_rules(s, picks)` (a plain order that is not ENTER: for the E9 tests, with `asked(prefix)` to check the
order was really the one scripted), the test's own
doorway frame (`BACK`, `FRONT`, `HALL_LIVING`, `KITCHEN_LIVING`, and the doorways on that a team covers once it holds the
kitchen or living room, `KITCHEN_HALL`, `LIVING_KITCHEN`, with `out`, `outward`, `lateral`, `in_funnel`, `in_room`,
`beside_door`, `corners`, `faces_through`) and the radio (`calls(t, step, id)`, `first_call_time`;
callouts carry `entry_step`; `radio_claim(c, opening, into, place, frame)`, a puppet teammate's claim, `place` its slot and side). The per-frame sampler and "it went in by entry" are `tests/_ai/entry_watch_probe.gd`
(`const EntryWatch := preload(...)`): `watch`, then `path_of`, `pos_at`, `first_stop_in_room`, `funnel_entries`,
`first_in_funnel`, `last_in_funnel`, `longest_pause_in_funnel`, `time_facing_through`, `share_facing`, and
`check_entered(t, samples, id, door)` for the E9 tests. The brain is read through `debug_entry()` and `debug_room_zones()`.

E10 to E15 are covered by `entry_clear_within_benchmark` (E10), `entry_reloads_before_crossing` (E11), `entry_stack_last_covers_rear`
(E12), `entry_short_room_two_go_in` (E13), `entry_hostile_in_view_holds_outside` (E14) and `entry_corridor_doors_not_passed` (E15), which
carry no `gap` tag (`tools/run_tests.sh --include-von --require-von entry` runs them with the others). A behaviour not built yet is
written the same way: a red test tagged `gap`, the spec in `docs/`. E15 has scripted tests of its mechanism too
(`entry_guard_secures_passed_doorway`, `entry_guard_enter_walk_secures_passed_doorway`,
`entry_guard_enter_walk_with_team_keeps_together`: one mechanism each, scripted Von). The six real-Von tests
run the whole pipeline with the **real Von server** (`requires_von`, paced in real time, so their timeouts are wall-clock):
the actors are plain `invader`s with match defaults (no switch, no timer override, only a premise such as a part-spent magazine), the world is placed so the doorway under test is the natural pick,
and each test first `require`s that the AI claimed that doorway, so a different Von choice reads in the bundle as a set-up
finding, not as the doctrine gap. Their maps: the box room (`Maps.box_room`, `Entry.BOX`) and the corridor spine
(`Entry.SPINE_A/B/C`). A `gap` test that turns green gets its tag dropped (a run fails a passing gap test until then).

- Two invaders that claim a doorway on the same frame settle their slots by instance id: the first actor declared
  gets slot 1 on a tie.
- From beside a door you can see the opposite door-wall corner through the gap, so what the pie leaves hidden is
  geometry, not a rule: assert that hidden corners are on the door's wall, not that both are.
- A defender meant to be unseen from outside has to be behind the jamb from every spot the entrant visits (stack,
  arc, the walk there), e.g. tucked against the door's wall well along from it.

**Doorway views (E18, tag `door_view`).** `tests/_ai/door_view_probe.gd` (`const View := preload(...)`) holds the test's own copy of a doorway's view (`polygon`, `in_view`: the
spec numbers `DEPTH` 450, `AVOID_RATIO` 2.0, `AVOID_SLACK` 300, `PASS_CLEAR_TIME` 60 are consts there, so a test checks the plan and not the code) and the reads on a `watch` sample
set (`first_in_view`, `time_in_view`, `longest_pause_in_view`, `axis_crossed_at`, `crossing_span`, `time_covering`), plus `wait_wall` (waits until a span has passed both on the wall clock and in sim time, pacing the sim
to real time meanwhile; the memory ages on `GameClock`, so the sim-time half is the one that ages it). The tests: `entry_route_round_door_view_outside` / `_inside`, `entry_secure_exterior_door_then_cross`, `entry_pass_far_out_secured` (real Von, gunfire heard as the premise),
`entry_cleared_room_pass_expires` (scripted, about 65 s of wall time) and `entry_route_band_as_walked` (scripted, the snapshot's wording); `navigation/avoid_map_carves_the_views` tests the map.
`entry_split_stack_criss_cross` (E19, real Von) uses the view to check a split stack: two invaders at the back door from north and south, neither walking across the view.
An invader that starts south of the back door outside its view (e.g. (990, 450)) and joins a stack on the north splits it (E19); a test that
wants a one-sided stack starts its late joiner on the stack's side (the E16 tests start `b` at (980, -70)).

## Stack tests (tag `stack`)

`tests/ai/stack/stack_*_test.gd` pin down the human's place in an AI stack (E16 in `docs/tactical-entry.md`), on the Terrace house and the
back door like the entry tests. A **puppet with the invader faction** stands in for the human, and the test gives it the stack radio the way
Main does: declared with `s.squads({ "human": id })` and read with `t.world.player_stack` when the test needs a squad too (`Stack.require_human_leads(t, squad, me)`
requires that premise: the stack handed its squad, which the human leads), else in `run`:
`Stack.attach(t, id)` (`tests/_ai/stack_probe.gd`, `const Stack := preload(...)`, which loads `PlayerStack` by path and calls
`attach(character, rooms, t.world.openings)`; null before the feature exists). The stack is read through `view()` (`Stack.mine`,
`Stack.slot_point`) and the human's radio through the usual `Entry.calls(t, step, &"me")`; `Stack.walk` takes the puppet through points
(`Stack.crossing(door)` goes in through a door). A late AI joiner is held back like in `entry_ally_joins_stack` (`tuning:entry:enabled` false,
`movement:speed` 0) until the human has its slot. `stack_player_slot_von` runs the whole thing with the real Von server (`requires_von`).
`stack_ai_goes_round_player_in_slot` declares Main's match instead (`s.declared_match`, below) and its human is the player's own character and
controller, given its stack through `MatchBuilder.bind_player`. The UI half is `tests/ui/stack_markers_draw_test.gd` (a fake stack with a
`view()`), the wiring `tests/general/stack_player_wiring_test.gd`.

## Bodies in the way (issue #53)

`tests/_ai/bump_probe.gd` (`const Bump := preload(...)`) measures "walks into" off public state only: `watch(t, who, duration, stop)` records
every frame a character steers (`movement.move_input`) within 60° of another it touches (centres under 31 px) as a bump, with whether the other was at
rest and how far it was shoved; `of_kind`, `collisions` (a head-on pair's two bumps as one collision), `describe`, `tally`, `totals`;
`pressed_watch(walker, other)` is a clock of the walker standing pressed against the other (still, centres under `PRESSED_GAP` 45 px: what `keep_off`
leaves of a walk into a body, short of a bump), called once a frame, against `PRESSED_MAX` (0.5 s). The
mechanism tests are `tests/ai/movement/npc_*` (scripted Von, a puppet teammate standing still), the scenario `tests/ai/entry/entry_team_no_bumping`
(real Von, four invaders placed as a match places its team: `s.declared_match` through `tests/_ai/house_probe.gd`). A test that a held walk re-plans reads `debug_state()["decisions"]` / `["decision_reason"]`
("way blocked"): an auto-picked level asks Von nothing (`tests/ai/entry/entry_held_walk_replans` for an entry's walk).

**A match built as Main builds one.** Every test world is staged as Main's match is (`MatchBuilder.stage`, `wait_nav` on: it waits until
the navigation maps answer with the world before an actor spawns, and Main's match waits the same way, `general/match_nav_ready_before_spawn`).
A test that wants Main's whole match declares it (`s.declared_match`, read with `t.world.match_handle`); its human may be a test actor: in
`tests/ai/stack/stack_ai_goes_round_player_in_slot` it is the player's own character and controller (no input), joined to the invaders
and handed its stack radio as a match's human is (`MatchBuilder.bind_player`). A test of Main itself runs Main whole through its public
members with `tests/_main/main_probe.gd` (`const MainProbe := preload(...)`; not a test): `open(parent, exports, player_at := ZERO)` (Main with
the children `main.tscn` gives it that `_ready` reads, `Player`, at `player_at`, and `SetupMenu`, without the Von launcher and the command
server; it opens the setup window, as a fresh launch does, or with the Engine `skip_setup` meta set while it enters the tree builds its
match at once, as a scripted restart does: `general/match_nav_ready_before_spawn`), `viewport(t)` (a `SubViewport` with a `World2D` of its own, so fresh physics and navigation maps, as each
match's), `setup_menu(main)`, `house(layout, parent)` (a `TestSetup` layout built as the match's `house`) and `close(t, node)` (puts back
what Main changed outside it); the test then starts a match with `Main.start_match(spec)` or reads `SetupMenu.current_config()`. No test
reads or writes a private member of `main.gd`.

## Leadership tests (tag `leadership`)

The rules are `docs/leadership.md` (LD1 to LD18, each with its tests named under it); `tools/run_tests.sh leadership` runs them, the four
real-Von ones (`ai/decision/order_fight_then_resume`, `ai/combat/defend_room_stays_inside`, `ai/decision/von_request_across_pause`,
`ai/combat/ambush_vs_stack`) with `--include-von --require-von`. They are spread by domain: the clock in `tests/ai/perception/clock_pauses` (LD1 also names
`memory_matches_reference`, which is not tagged `leadership`), the order transport, ORDER node, progress radio, a refused order and what an order stops (a walk, not a fight: `order_stops_walk`, `order_fight_goes_on`, `order_retreat_goes_on`) in `tests/ai/decision/` (`order_*`, and
`unordered_state_unchanged`, which compares an unordered NPC's first walk and state text with the capture `unordered_state_unchanged.json`
beside it), defending a room in `tests/ai/combat/defend_room_*`, the ambush (LD15) in `tests/ai/combat/ambush_*` (`ambush_door_post`,
`ambush_ends_on_shot_at`, and `ambush_vs_stack` with real Von), the ordered stack in `tests/ai/entry/order_stack_*` (scripted, the Terrace
house's back door; the held stack of LD13 in `order_stack_hold_for_go`, `order_stack_go_latched`, `order_stack_hold_human_go`,
`order_stack_hold_leader_dies`), the frag entry (LD14) in `tests/ai/grenade/order_frag_*` (`order_frag_entry`, `order_frag_held_then_go`,
`order_frag_no_frag_goes_quiet`), the squad and Main's wiring in `tests/general/` (`squad_leader_rule`, `squad_succession`,
`squad_done_order_not_cancellable`, `squad_go_and_ambush`, `lead_rank`, `command_menu_wiring`: also the held stack and the menu's Go) and the UI in `tests/ui/` (`command_menu_items`, `command_menu_docks_right`, `command_menu_docks_left`, `command_menu_clear_of_overlay_bar` / `_centre` / `_crowded`, `command_menu_label_matches_order`, `order_markers_draw`, `leader_overlay_draw`,
and `setup_menu_config`'s "Lead the team").
A test with one squad per side declares it (`s.squads`, the human leader a puppet named by `human`; read with `t.world.squad(faction)` and
`t.world.player_stack`). The shared helper is `tests/_ai/order_probe.gd` (`const Order := preload(...)`; not a test): `squad(t, faction,
members, leader)`, a squad built and bound by the match's own rule (`MatchBuilder.build_squads`) in `run`, for the squads no setup declares
(two squads of one side, in `general/squad_leader_rule` and `ai/decision/order_progress_radio`, each saying why in its header), `issue` / `post` / `view` /
`stack_order` (a stack the way the menu asks for it, `mode` and `wait_go`) / `go` (the leader's go, LD13) /
`member_view` / `orders`, the radio
(`progress`, `ordered_claims`, `raw_calls`, `first_time`, `all_called`, `by_slot`), `gunfire_near` (forces a decision without touching the brain),
`pause_for(t, wall_s)` (holds the tree paused for that much wall time: the test clock stops with it) and the back door's click points (`BACK_NORTH`, `BACK_SOUTH`,
`BACK_ON`, `BACK_INSIDE_NORTH`, `back_side`), with the spec's numbers as consts (`ORDER_READY_CAP`). The brain's reads are
`tests/_ai/order_brain_probe.gd` (`const OrderBrain := preload(...)`: `brain`, `ordered`, `decisions`, `primitive`, `params`, `on_order`,
`levels`, and where its entry has it stand at the back door, `stack_point` and `stacked`). The command menu and the order markers are
`tests/_ai/order_menu_probe.gd` (`const OrderMenu := preload(...)`: `command_menu`, `items`, `item`, `labels`, `choose`, `tick`, `click`,
`view_still`; `player_screen` sizes a headless root
viewport to the project's window, as a real screen is (a real window keeps its own size unless `exact`, for a premise built on the
project's size: that size is then stretched over the window, and `click` maps through the stretch; the grenade perf guards
read it too, so the bodies a player would see are drawn headless), and `check_dock` is the dock-side tests' run: the panel's rect covers neither
the click nor a selected teammate; `check_clear_of_bar` the overlay-bar ones, Debug on: with a real `OverlayToggles`, the panel
clears the bar too). The squad,
menu and markers are loaded by path and read duck-typed, so a missing piece fails an assertion that names it.
LD17's tests are `tests/ai/entry/order_stack_waits_for_leader` (the human puppet's `PlayerStack` claim says `leader`) and
`order_stack_joiner_grace`; LD18's is `tests/ui/stack_markers_draw` (a fake squad view's `stacks`); a dead end's refusal (D21) is
`tests/ai/entry/stack_dead_end_refused`.

**Following, the leash and the rally (LD19 to LD28).** The shared helper is `tests/_ai/follow_probe.gd` (`const Follow :=
preload(...)`; not a test): the spec's numbers as its own consts (`FOLLOW_GAP`, `FOLLOW_STEP`, `FOLLOW_CAUGHT_UP`, `FOLLOW_RING`, `FOLLOW_RINGS`,
`FOLLOW_STILL_TIME`, `FOLLOW_RETARGET`, `FOLLOW_ARRIVE`, `LEASH`, `LEASH_BREAK`), so a test checks the spec and not the code, and the band a follower keeps
(`band_p50(i)`: the `i`-th follower's place in the file plus `BAND_LAG`, 45 px of walking lag, at the median; `BAND_P90`); the squad
is the test's declared one (`s.squads` or `s.declared_match`, read with `t.world.squad`), built and bound as a match's; a member's reads (`brain_of`, `act`, `following`, `walk_target`, `entry`); the radio
(`raw_joins`, `raw_orders`, `calls_of`, `own_claims`, `first_call`, `clears`); and the leash
chase's world (`chase_hall`, shared by `ai/combat/leash_no_chase` and its contrast `leash_free_chase`, which binds no squad). The tests
call the squad itself (`follows`, `follow_spot`, `leader()`, `view()`) and its tunables on `SquadFollowConfig` (`leash`); a squad read
that only answers the code's own value (`follows`, `SquadFollowConfig.leash`) is a `require` premise, and the behaviour the spec describes is the check.
A watch of the team is `tests/_ai/follow_watch_probe.gd` (`const FollowWatch := preload(...)`): `new_watch`, `tick`, `watch`, `asked` (the Von
questions of a member's walks), `gaps`, `took`, `acts_of`, `went_through`, `percentile`, `off_spot_tick` and `step_up` (the
human walked up to `STEP_UP` beside the back door, the rally tests' claim).

**Where a stack stands (E20 to E22) and every member reaching its slot.** `tests/_ai/slots_probe.gd` (`const Slots := preload(...)`; not a
test) judges slots from the house's own data and the test's own geometry (rooms, wall plane, navmesh, carved furniture, its own copies of
the other doorways' views and funnels): `frames` / `frame` (a way in's door frame), `world_of`, `entry_geometry` (the AI's `AgentEntry`, loaded
by path), `layout(g, count, side)` (the slots, read only through the published rule `StackLayout.slots`, perception's
`stack/stack_layout.gd` loaded by path) and the spec's numbers (`MAX_STACK`, `ROOM_INSET`, `STACK_SPACING`, ...). The checks are three
probes beside it: one per rule for a point in `tests/_ai/slot_rules_probe.gd` (`const SlotRules := preload(...)`: `in_stack_room`,
`on_navmesh`, `reachable`, `clear_of_other_doors`, `in_other_funnel`, `in_other_view`, `clear_of_furniture`, `side_has_room`, `room_for_one`,
`in_wall_band`, `view_count`, `tail_fault`, and `ray_to_edge`, how far from a point along an axis to a rect's edge); the faults a slot, a stack or a short wall's chain breaks in `tests/_ai/slot_faults_probe.gd`
(`const SlotFaults`: `point_faults`, `stack_faults`, `short_wall_faults`, `is_short_wall`, `capacity_text`); and rule 6's ways in, the rule
a way in's slots answer to and what each holds, in `tests/_ai/slot_capacity_probe.gd` (`const SlotCapacity`: `way_kind`, `dead_end_capacity`,
`wall_capacity`, `views_capacity`, `open_floor_capacity`, `wall_spots`, `fewest_views_bar`). `tests/ai/entry/stack_slots_sweep` runs them over
every generated floorplan. Beneath them two native suites
feed plain claim dicts to the stack module, over the shared speakers and callouts of `tests/_ai/stack_radio_probe.gd` (`const StackRadio :=
preload(...)`: `speaker(suite, dead)`, freed with the suite's case, and `callout`): `tests/ai/stack_claim_suite.gd` (`StackClaim`'s codec, its
not-a-claim, step and join rules, a `ClaimLedger`) and `tests/ai/door_stack_suite.gd` (`DoorStack`'s slot rules: same-frame ties, move-up, the
human's slot, a split stack's crossing order, `released`, layout rows). `tests/_ai/reach_probe.gd`
(`const Reach := preload(...)`) runs an ordered stack, held for the go, from given starting places (`frame`, `click`, `run(t, f, lead, side,
starts)`, the members the keys of `starts`) and checks each member by its own measure: in the slot it last claimed within `SLOT_REACH`, in time (its keep-out route's
walk, `keep_out_route`, plus slack, timed from its last D4 detour), never the back of the stack nor an `abort` (a rise only as the other half of
a real move-up, `move_ups` / `_check_move_up`), never the doorway's view nor its front close in when a way round exists (`way_round`,
`front_crossings`), no bump; the nine `tests/ai/entry/stack_reach_*` use it.

## Investigation tests (tag `investigate`)

`tests/ai/investigate/` pin down how gunfire heard outside or inside the house is worded for Von
and answered (issue #40: defenders leaving the house). The shared helper is `tests/_ai/investigate_probe.gd` (`const Probe :=
preload(...)`): `world(s, kind)` (the terrace house, one NPC in the hall, radio and trespass hostility off, Von left to the caller),
`gunfire(at)` (a hit event nobody known fired, heard from `Probe.OUTSIDE` / `Probe.INSIDE`), `levels` / `asked_about_investigating`.
Scripted ones (`investigate_outside_lead_offers_stay`, `investigate_lone_lead_is_asked`) check the wiring. The three `*_von` tests
(`requires_von`, `--include-von --require-von`) check what a real Von decides: the defender stays in, still investigates gunfire inside,
and an invader still investigates the same gunfire outside. After rewording any of what Von reads about leads, run them with
`tools/von_probe.py` (its `investigate_outside_lead_*` scenarios).
Footsteps (`docs/hearing.md` H1, tag `hearing`): `ai/perception/footsteps_heard_by_gait` (scripted: puppets walk, run and crouch lanes at set distances behind a
wall from a held defender, read off `debug_memory()["footsteps"]` and the `footfall` events' `character` / `crouched`) and `ai/investigate/footsteps_lead` (real Von).

`defenders_stay_in_house_quiet` (scripted) and `defenders_stay_in_house_quiet_von` (real Von, invaders outside as at the start of a match)
watch every defender of a generated house (`tests/_ai/house_probe.gd`: `house(s, seed, defenders, invaders)` declares the house and a
match over it, `s.declared_match`, placed and armed as Main's; `side(t, faction)` reads one side's NPCs off `t.world.match_handle`; `watch`, whose failure message carries each
defender's trail and what Von was last asked) and sweep with `--seed=N`. `move_stops_on_arrival` gives
the scripted Von a real server's reply time by raising `DecisionStub.latency_frames` in `run` (`von_script` registered it, so it is restored after the test).

## Flanking tests (tag `flank`)

`tests/ai/flank/` pin down how the AI weighs and takes the sides of a target: frame geometry, route
safety, ally and radio claims, shot and cover wording, territory, and the walk itself. They are
scripted-Von tests (no server); `tools/run_tests.sh flank` runs them. What they assert is written in
`docs/flanking-behavior.md` (behaviours F, B1 to B9, C); each test header names the behaviour. A test that
asserts a behaviour the AI does not show yet is written first, left red and tagged `gap`
(`tools/run_tests.sh gap`); none are open now.

- **Realistic maps** (`tests/_ai/flank_maps.gd`, `const Maps := preload(...)`): `Maps.house(s)`,
  `Maps.spine(s)` and `Maps.warehouse(s)` lay out rooms, doorways, corridors and cover with
  `TestSetup.layout`, and expose landmark consts (doors, wall and room points). Call the map first, then
  `Flank.rules(s)`. Flank points sit 220 px from the target and snap to the navmesh, so a room-sized map
  gives some sides behind walls; choose positions from a `Flank.dump(brain)` of the situation.
- **Shared helper** `tests/_ai/flank_probe.gd` (`const Flank := preload(...)`; not a test): `rules`,
  `target`, `npc`, `ally`, `radio`, `settle`, and the reads below.
- **Observe through the controller's public reads.** `debug_zones()` lists every flank side the snapshot
  weighed *including those the planner then dropped*, with its `desc` and `tags` (`held`, `held_by`,
  `crosses`, `crosses_name`, `no_shot`, `heading`, `lane`, `clear_shot`, `cover`, `inside`,
  `route_exposed`, `ally_lane`);
  `debug_state()["decision"]["levels"]` holds what each level offered. So "dropped because X" is `zones`
  says X and `offered` lacks the id. `Flank.zones/offered/offered_sides/dump/level/side_of_act` wrap these;
  `Flank.side_of` is the test's own copy of the target-frame maths (left is the target's own left, so a
  west-facing target's left is south). With several hostiles known, `debug_zones()` mixes their sides:
  give `Flank.zones(brain, target_pos)` the target and make the NPC fight it with `Flank.prefer_target`
  (the nearest hostile is otherwise the first option and gets picked).
- **Hold the NPC and settle** (`Flank.npc` + `Flank.settle`): `movement:speed` 0 and a 0.4 s commit and tactic
  cadence, so it re-decides from a fixed spot and `settle` waits for a finished walk. A walking test holds
  the NPC until `settle`, then sets `brain.tuning.decision.max_commit_time` back to 6 and `npc.movement.speed` to 150.
- **Set the target's frame before the first frame** (`Flank.target`): its `facing` and `movement:aim_point` are
  props, because a puppet's `movement.aim_point` defaults to the origin and turns it that way until `aim_at` runs.
  Give targets and allies a huge `max_health`; the NPCs shoot while they wait.
- **Radio claims** are real `callout` events posted with `Flank.radio` from an ally puppet the NPC cannot
  see (behind a wall, or far off). An ally it can see holds the side it stands on by name, without
  "(radio)". Two or more live invaders get different `tuning.decision` `max_commit_time` / `tactic_interval` /
  `decide_interval`, otherwise they decide on the same frame and claim the same side.
- **Route-safety rules decide which sides exist.** A route within `tuning.tactics.route_clearance` of a hostile is dropped,
  and in open ground the straight route to a rear point passes the target. Tests about other rules set
  `route_clearance` low (0 for the group tests, 40 for the ally lane) so only the rule under test acts, and
  say so in a comment.
- **An ally only counts if the NPC sees it.** The NPC weighs allies by sight (a 110° view cone toward its
  target, plus a 48 px bubble) or by radio, so a test about an ally's line of fire or side must put the ally
  within 55° of the NPC's line to the target, with no wall or pillar between. An ally outside it leaves
  `allies` empty and no rule fires. The lane rule also tests the NPC's *route*: a route that passes between an
  ally and the target is dropped, so place a held-side ally off the routes the test expects to be offered.
- **TTL lapse is in sim time.** Memory ages on the game clock (`GameClock.msec()`, physics frames, `docs/leadership.md` LD1),
  so a callout or contact lapses after its ttl of test time (`t.seconds`) as in the game, and not while the tree is paused
  (`ai/perception/clock_pauses`).
- **Flank point sampling** prefers any sampled point with a clear shot, so a "line blocked" scenario needs
  a barrier across the whole arc (a row of shelves), not one piece.

## Outfit tests (tag `outfit`)

The rules are `docs/outfits.md` (O1 to O15, each with its tests named under it); `tools/run_tests.sh outfit` runs them. They are spread by domain
(`tests/character/hit_zone_by_bullet_height`, `outfit_weight_slows`, `outfit_art`, and the styles' `style_look` (tag `style`, with
`tests/general/match_styles`); `tests/projectile/helmet_*`, `soft_vest_*`, `plate_*`, `armour_stop_feedback`,
`frag_blast_cut_by_vest`; `tests/items/loadout_outfit`; `tests/ui/setup_menu_config`, `debug_panel_outfit`, `inspector_outfit`), all through
`tests/_outfit/outfit_probe.gd` (`const OutfitProbe := preload(...)`, not `Outfit`: that is the Items class): `wear` / `view` / `condition` (each false / `{}` / -1 without the outfit API; `require_api` is the named check),
`pin_height` (pins `BallisticsFlightConfig.bullet_height`; `STAND` / `CROUCH` are a height in each zone), the spec's numbers (`ZONE_DAMAGE`, `PLATED_KIT`, `PLAIN_CLOTHES`)
so a test checks the doc and not the code, and shooting lanes (`lay_lanes`, `dress`, `volley`: real rounds with a gun's `GunConfig` numbers, or a frag's fragment, fired
square on at a target with a witness standing behind it to show whether a round came out), plus `art(c)` (the body's `drawn_art()`). `--changed` maps
`tests/_outfit` (an unknown helper folder) to the whole suite. **A test that counts gun damage pins the bullet height** (a random height picks a zone, and a head
shot deals twice a torso's). A test reading a dead body's drawing keeps it near the living actors (the camera drops the dead from its framing, and headless it
sees only about 160 px plus the 120 px cull margin) or follows it alone with `camera_follow`.

## Grenade tests (tag `grenade`)

The rules are `docs/grenades.md` (G1 to G19, each with its tests named under it); `tools/run_tests.sh grenade` runs them, the scenario tests
with `--include-von --require-von`. They are spread by domain (`tests/items/grenade_*`, `loadout_grenade_counts`; `tests/projectile/frag_*`,
`grenade_friendly_fire`; `tests/physics/frag_blast_pushes`, `explosion_fx`; `tests/character/stun_*`; `tests/audio/grenade_sounds`;
`tests/general/camera_shakes_on_explosion`; `tests/ui/stun_screen_whiteout`) with the AI ones in `tests/ai/grenade/`, all through
`tests/_ai/grenade_probe.gd` (`const Probe := preload(...)`): `arm(character, stuns, frags)` (a test world keeps the default inventory, so each test
arms the thrower the way Main does, at the start of `run`), `throw_at`, `live`, `raw` / `booms` / `stuns` (bus events with their sim time) and the numbers of the spec
(`MAX_RANGE`, `FLASH_RADIUS`, ...) so a test checks the doc and not the code. What a blast or a stun does at a distance by the spec is
`tests/_ai/grenade_spec_probe.gd` (`const GrenadeSpec := preload(...)`: `blast_damage`, `flash_scale`, `expected_blind`, `expected_deaf`, and
`everywhere`, the audio tests' range table); the AI reads and a scene round a grenade are `tests/_ai/grenade_ai_probe.gd` (`const GrenadeAi :=
preload(...)`: `offered`, `acts`, `wait_act`, `callouts`, `grenades`, `hostile`, `place`, `line_clear`, `safe_from_frag`, `shielded`, `known_contact`, `watch_until_thrown`, `check_held_at_old_spot`, `check_sees_again`, `check_thrown_from_outside`, `shot_runs_into` (the line back from a `shot_from` memory crosses a room), `plain_escape` (`AgentThrow.escape` worked out the plain way, every candidate snapped, judged and routed) with the `escape_threat` / `escape_runner` it takes, and
`character_rids`, the rids of the `characters` group: what its rays and `throw_spot_probe.gd`'s look past). The scenario tests
in `tests/ai/grenade/` run the whole AI pipeline with the real Von server and `require` the premise first (that the AI took the GRENADE / STUN ENTRY path), so a
different Von choice reads as a set-up finding. A hall of 100 px or less with a sofa in it is **sealed in the navmesh** (the lane left is under an agent body wide) and
a route to the far side then runs outside the house: give a scenario hall at least 140 px when the NPC has to walk past a piece of furniture.
The suspect-room STUN ENTRY tests (`stun_entry_*`, G18) share `tests/_ai/suspect_probe.gd` (`const Suspect := preload(...)`: `world` the bare Terrace house
and a stack of two in the back garden, `arm`, `watch`, `first_search`, `check_stun_entry`: the stack's first SEARCH / INVESTIGATE decision must be STUN ENTRY by the back door
and a `bang` radioed); each adds the one thing that makes the kitchen suspect at the start of `run`. The wording they rest on is measured by `tools/von_scenarios/stun_entry_*.json`.
The throw-spot tests (`grenade_throw_spot_*`, `grenade_walks_to_throw_spot`, `grenade_shots_origin_throw_spot`, G17's throw spots) share
`tests/_ai/throw_spot_probe.gd` (`const Spot := preload(...)`: `throws` (the `grenade` zones of `debug_zones()`), `from_of`, its own `lob_clear` (one ray, nothing above 50 on the
line), `hand_lob_clear` (that lob from the thrower's hand, `Character.inventory.throw_release_offset`, along a band 8 px either side), `THROW_RANGE` (550), `walk` (a `NavBuilder.route` reach and length), `any_lob_along`, `note` / `describe`, which follow each decision walk with where the NPC stood when it began, and `watch_first_combat`, those walks until the NPC's first COMBAT decision and its throw). A throw's
`throw` event is at the hand, about 16 px from the thrower's centre. The mechanisms the scenarios cannot reach are scripted-Von tests: `grenade_range_drift`, `throw_dropped_when_lob_blocked` and `throw_committed_in_windup` use `von_script(rules, 30)`
(slow answers) to change the world while a question is in flight; `evade_replans_when_spot_in_line` rolls a grenade on by moving it once it is at rest (a resting
`ThrownGrenade` stays where it is put) and posting the `grenade` rest event it would post, which a turned-away NPC hears (a character moved with `global_position`, a piece of furniture shoved onto the lob: it must be `freeze`d first and
the teleport made a frame later, or the physics step puts a free body back), and the four `bang_fallback_*` tests run a stack of two at the Terrace house's back door through
`tests/_ai/bang_probe.gd` (`const Bang := preload(...)`: `rules` SEARCH > STUN ENTRY > that doorway, `stack`, `arm`, `radio_mate` for a teammate that is a puppet radioing its part of
the stack, `note_acts` / `took`).

## Lighting tests (domain `lighting`, `tests/lighting/`)

The rules are `docs/lighting.md` (L1 to L10, each with its tests named under it); `tools/run_tests.sh --domain=lighting` runs the
eleven (`lighting/stun_flash_light` reads the stun's held-then-faded flash off `flashes()` each frame). The shared helper is `tests/_lighting/lighting_probe.gd` (`const Probe := preload(...)`; not a test): the plan's numbers as
consts (`AMBIENT`, `ITEM_LIGHTS` 15, `PER_FLOOR` 12, `FLASH_NEAR`, the pool profile bounds `OVERHEAD_HALF_MIN` / `LOW_HALF_MAX`,
the smoothness bound `SMOOTH_SAMPLES` / `SMOOTH_STEP_MAX` and the street pool's `STREET_POOL_MAX` / `STREET_POOL_CENTRE`), the test
world's `WorldLighting` (`lighting`, `require_lighting`: the one in the group `world_lighting`, with its four reads), the light-giving kinds told apart by the pieces' public fields (`light_kind`), a
piece's `declared` lights / `lights_of` / `dropped_of`, a light's pool profile (`profile`: its gradient at a share of its radius;
`largest_step`: its biggest jump), the floors and what reaches them (`floors`, `floor_mask`, `light_box`: a light's texture box,
`reaches`), and the occluders (`casting`, `holds`, `occluders_at`, `own_occluders`). Everything else is read off plain Godot nodes
(LightOccluder2D, PointLight2D, CanvasModulate, DirectionalLight2D, the overlays' `material`). `rhythms_seeded_per_piece` builds
its room twice, each in a `SubViewport` with a World2D of its own, and lights each with `WorldLighting.light(root, seed)` itself.

## Vehicle tests (domain `vehicle`, `tests/vehicle/`)

The rules are `docs/vehicles.md` (V1 to V9, each with its tests named under it). Thirty puppet-driven tests in `tests/vehicle/`, plus
`tests/audio/vehicle_sounds_test.gd`, `tests/audio/vehicle_door_tone_test.gd`, `tests/general/camera_zooms_out_driving_test.gd` and `tests/general/use_vehicle_key_test.gd` (a
`player` actor and injected E). The shared helper is `tests/_vehicle/vehicle_probe.gd` (`const Probe := preload(...)`; not a test): the plan's
numbers as consts (`DOOR_REACH`, `BOARD_MAX_SPEED`, `EXIT_MAX_SPEED`, `HARM_MIN_SPEED`, `DOOR_OPEN_TIME`, `FOLD_TIME`: `board_animation_is_continuous`
checks the door's and the fold's measured ease against the last two, within 0.4× to 2×) and each kind's door table
(`CAR_DOORS`, `VAN_DOORS`), so a test checks the spec and not the code; `ready` / `has_reads` (a read that does not exist fails a `require`
instead of a script error), `config_value(holder, prop)` / `kind_value` (a Vehicles holder's static read by class name; a missing holder or var is an error, never a fallback), the door and seat reads (`door`, `open_of`,
`seat_of`, `occupant`, `watch_doors` / `opened`) and the draw layers (`layer`, `absolute_z`, `draws_above`). Beside it, the vehicle frame
in `tests/_vehicle/vehicle_frame_probe.gd` (`const VehicleFrame := preload(...)`: `forward`, `right`, `outward`, `stand_point`, `edge`,
`gap_to_solid`, `tail_offset`, `local_velocity`, `pivot`, `outward_slip`, `along`), and placing (`place`, `move_vehicle`), the ride (`exit`,
`board_by`) and driving (`reach_speed`, `hold_speed`, `hold`) in `tests/_vehicle/vehicle_ride_probe.gd` (`const VehicleRide :=
preload(...)`). Everything goes through the drivable contract (interface 19) duck-typed. `tools/run_tests.sh --domain=vehicle` runs the domain; `--changed` on `scenes/vehicle/` runs vehicle, character,
items, interaction, projectile, physics, objects, ai, perf, audio and general.

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
  `tools/test_gdunit_panel.py` runs the tests as the editor's GdUnit panel does ("The GdUnit panel", above).

## Behaviour switches (`test_switches.gd`)

One data table. A row maps a name to existing knobs:

- `actor: { child, props }` sets those props to `on` on that child of every actor (`child` `""` = the character itself), before it
  enters the tree; `controller: true` in place of `child` targets the actor's controller child (the one with `control`,
  interface 7, found by `TestContext.controller_of`), which is how every `ai.*` row reaches the NPC's tunables, a prop an indexed path
  (`tuning:<topic>:<name>`, set with `set_indexed`);
- `world: { node, props }` sets props on a world node;
- `static: [[Script, prop]]` sets that `static var` to `on`;
- `[Script, prop, off_value]` is for a non-bool knob: on keeps its tuning, off sets `off_value`.

Statics are restored after every test (`TestWorld.restore`). Current switches:

| Switch | What it controls |
|---|---|
| `ai.vision` | Whether NPCs can see. |
| `ai.callouts` | Team radio callouts, sent and heard. |
| `ai.pursuit` | Whether NPCs chase hostiles. |
| `ai.territory` | Defender confinement to the house. |
| `ai.hostile_on_sight` | Hostility toward anyone seen. |
| `ai.hostile_on_trespass` | Hostility toward anyone inside the house. |
| `ai.hostile_on_attack` | Hostility toward an attacker. |
| `ai.posture` | NPCs crouch while fighting in place (`tuning.pace.posture_enabled`). |
| `ai.entry` | Tactical entry (`tuning.entry.enabled`; on in the invader preset). |
| `ai.entry_guard` | The entry guard (`tuning.entry_guard.enabled`, on by default; needs `ai.entry`): any walk into an uncleared room goes in by entry. |
| `nav.rebake` | `NavUpdater.enabled`. |
| `audio.sound` | `SoundConfig.enabled`: shots, impacts, footsteps, reloads and the grenades' throw, bounce and burst make `sound` events and voices. |
| `physics.blood` | `BloodConfig.enabled`. |
| `physics.footprints` | `BloodPrintConfig.footprints_enabled`. |
| `physics.smear` | `BloodSmearConfig.enabled`. |
| `physics.debris` | `PhysicsConfig.debris_enabled`. |
| `physics.hit_particles` | `PhysicsConfig.hit_particles_enabled`. |
| `lighting.enabled` | `LightingConfig.enabled` and General's `LightMasks.shadows`: the dusk lighting (ambient, sky, piece lights and fixtures, flashes) and every occluder (walls, pieces, characters). The test world is lit like a match by default; a sandbox that lights itself turns it off. |
| `projectile.flyover` | `BallisticsFlightConfig.cover_flyover_scale`, 0 when off. A test that needs a chosen outcome instead pins `BallisticsFlightConfig.bullet_height` (0–100) with `set_static`. |

To add a switch, add a row. When the behaviour has no knob yet, add a master `static var` to that
domain's config holder, guarded at its one spawn point (the way `BloodConfig.enabled` gates
`BloodWound.record`).

## Files

| File | Role |
|---|---|
| `game_test.gd` (`GameTest`) | Base class. |
| `test_setup.gd` (`TestSetup`) | The declarative builder. |
| `test_context.gd` (`TestContext`, an **Object**) | What `run(t)` calls: waits, lookup (the actors, objects and vehicles read off `t.world`), the event log, assertions and `finish`; the session sets `world`, `rooms` and `time` and appends to `events`. Two parts, each a `RefCounted` built once that holds nothing of the context: `verdict` and `bundle`. The test session frees it at close, which discards any test coroutine still parked on it. |
| `test_verdict.gd` | The context's `verdict`: `checks`, `logs`, `status`, `reason`, `expect_log(pattern, count)`, `on_log(ctx, entry)` (the session hands it each logged line), `conclude(ctx, manual)` (PASS / FAIL / TIMEOUT / SKIPPED, and GAP for a `gap`-tagged test that failed as expected) and `end(result)` (`finish` records the verdict). A method that records a check or ends the test takes the context at the call. |
| `test_bundle.gd` | The context's `bundle`: what a failed run's bundle carries, `traces` (`t.trace`), `shot_prefix` / `shots` and `screenshot(label)`, `snapshot(world)` (the actors', objects' and vehicles' state as plain data) and `plain_events(events)`. |
| `test_world.gd` | Builds a TestSetup into a sub-tree: statics and switches first, then the house, layout or arena with its objects, then the world stage as Main's match has it (`MatchBuilder.stage` with `wait_nav`: nav plus updater and the `NavDebug`, the dusk lighting, interface 20, none with `lighting.enabled` off, two physics frames (walls solid, navmesh live), then a wait, real time, at most `MatchBuilder.NAV_SYNC_MS`, until the planning map and the steering map are `NavBuilder.ready`), actors (each NPC bound by `MatchBuilder.bind_npc` before `_ready` — `rooms`, the house's `openings`, an invader's front entrance — positioned before they join the tree so one never overlaps origin furniture for a frame), a declared match (`MatchBuilder.populate`, `match_handle`) or declared squads (`squads`, `player_stack`, the `LeaderOverlay`), then world switches. Vehicles (`TestSetup.vehicle`) are placed after the nav wait and before the actors, followed by one more
physics frame so they are in the space. `build` is a coroutine. Also `restore()`, `set_overlay()` (through `MatchBuilder.set_overlay`) and `squad(faction)` (the declared squad of that faction, or null), which tests read as `t.world.squad(faction)` beside `t.world.match_handle` and `t.world.player_stack`. It has no bake, light, nav-wait or bind code of its own. |
| `arena_builder.gd` | The walled arena via `FloorFactory` / `WallFactory` + `WorldGen.wall_style()`, annotated with `WorldGen.annotate_layout`. |
| `layout_builder.gd` | A hand-laid layout: per-room floors and walls, doorways cut with `WallFactory.openings_for`, annotated with `WorldGen.annotate_layout` like a house. |
| `scripted_controller.gd` | The puppet controller. |
| `test_switches.gd` | The switch table. |
| (AI) `decision_stub.gd` | `DecisionStub`: the scripted-Von statics a TestSetup turns on (restored after each test); `DecisionBudget.per_frame` (`decision_budget.gd`) is set with `set_static` the same way. |
| `log_watch.gd` | The log tail (`begin(from_start)`, `poll`, `consumed`). |
| `test_catalog.gd` | `discover(root, domains, ids, skipped)`, `describe(path)` (descriptor dicts), `matches(entry, text)`, and the CLI selection helpers `csv()` / `shard()` / `load_costs()`. |
| `test_session.gd` | Plays one catalog test at a time, shared by the runner and the gdUnit suites: `start(entry)` builds its `TestWorld`, observes it on a `TestContext`, ticks its sim clock and timeout, routes the log to it and returns when it has ended; `close()` frees the world and returns the verdict record. Owns `print_result` and the bundles; the Von launcher wait and the real-time pacing are its `von` part's. |
| `test_von_gate.gd` | The session's `von` part (a `RefCounted` it builds once, holding the session): `include` / `require` (`--include-von` / `--require-von`), `launcher_parent` (where the one launcher of the process lives), `skip_reason(announce)` (a coroutine: the wait for the server, `NOT_LIVE` when none is live; `announce` is the session's `status.emit`), `pace()` (the real-time pacing of a Von test, each process frame) and `end()`. |
| `game_test_suite.gd` (`GameTestSuite`) | The gdUnit4 base of the wrapper suites: `cases(folder)` lists a folder's selected ids as one parameterized test's cases, `run_case(id)` plays one through a `TestSession` and maps its verdict to gdUnit's; restores and frames the runner window; joins the group `game_test_suites` and exposes `open_entry` / `open_ctx` for the coverage probe. |
| `unit_suite.gd` (`UnitSuite`) | The gdUnit4 base of a native pure-logic suite: the log gate per test, selected whole or skipped. |
| `test_batch.gd` | What one gdUnit run shares (static): its options (after `--`), the selection and shard, native-suite selection, the verdict records, the banner, the summary and `report.json` (`begin` / `add` / `finish`). |
| `test_report_hook.gd` | gdUnit's session hook (`project.godot`, `gdunit4/hooks/session_hooks`): starts and finishes a run given `--out`, and makes each native case a record. |
| `test_list.gd` | `run_tests.sh --list`: prints what a run with the same options selects. |
| `test_runner.gd` / `.tscn` | The in-game runner: interactive (`--play`, the browser's Play) and queued (`--queue`, "Run N checked") modes over a `TestSession`, the banner, overlay bar and camera, the Von launcher kept for the scene. No batch mode: batch runs are gdUnit's. |
| `tests/**/<x>_suite.gd` | The 27 wrapper suites (`extends GameTestSuite`, one parameterized test listing `cases("<folder>")`), `tests/_harness/harness_suite.gd`, and the native suites (`extends UnitSuite`). |
| `test_browser.gd` / `.tscn` | Hosts the UI browser window. Engine metas `test_selection` / `test_results` / `test_filter` survive the round trip through a test. |

## Gotchas

- **A body added this frame is not in the physics space.** A direct-space query (a shape query, a ray) on the frame a body was added
  misses it: it joins the broadphase at the next physics step (`TestWorld` waits one after placing vehicles).
- **A click at a world point needs a still view.** The test camera (the runner's, or the gdUnit suite's) eases in from where the previous test left it
  (and keeps easing while the tree is paused), and an injected mouse event is handled a frame after it was aimed, so a click aimed while
  the view moves lands elsewhere: such a test first waits for the canvas transform to hold still (`OrderMenu.view_still`, `tests/_ai/order_menu_probe.gd`,
  used by `ui/command_menu_items` and the dock and overlay-bar tests). It counts drawn frames (`Engine.get_process_frames()`), not
  physics frames: the camera moves once a drawn frame, and a window's first frames run several physics frames each, so five still
  physics frames can pass before the camera has moved at all.
- **A test camera reads its screen centre only while current.** Godot updates `Camera2D.get_screen_center_position()` only for the
  viewport's current camera, and the test camera stays current: a test that adds its own camera and reads where it looks calls
  `make_current()` on it (`tests/general/camera_zooms_out_driving_test.gd`).

- **Von tests are paced in real time.** `run_tests.sh` runs use `--fixed-fps 60`, so the sim outruns the wall
  clock and game-time timers (HTTP timeouts, the launcher's probe interval) fire early. While a `requires_von` test is open the test session sleeps each frame to
  1/60 s, because `Engine.max_fps` is not honoured under `--fixed-fps` headless. A cold Von start
  takes about 5 s.
- A test that ends mid-wait (a failure or timeout) leaves its coroutine parked. Godot may report
  "ObjectDB instances leaked" at process exit for it. That happens after the last log poll and is
  harmless.
- An NPC thinks on its first tick, so the world must be live before actors enter: the world stage
  (`MatchBuilder.stage`) waits two physics frames after the walls and navmesh are made (otherwise an NPC sees through room walls and
  plans on an empty navmesh), then until `NavBuilder.ready` holds on the planning map and the steering map (the one rule for a map
  that has taken in this world's regions). A map's iteration is built on a worker thread: under load (parallel shards) its id and
  region list update before queries do, and an NPC that snapped a point onto the empty map walked to the origin. That wait is
  in real time, so the test clock is stopped while the world builds (`_building` in the test session).
- The defender preset is `tuning.hostility.on_trespass`, and an arena counts as its house. Turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
