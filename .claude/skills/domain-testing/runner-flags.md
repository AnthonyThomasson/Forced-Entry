# Runner flags: the long reference

The `tools/run_tests.sh` flags `SKILL.md`'s "Running tests" leaves out.

- **Per-run output dir:** the wrapper gives every process a fresh `mktemp -d`, passed as
  `--log-file <dir>/godot.log` (engine flag) plus `--out=<dir>`. The report, failure bundles, shots, gdUnit's
  reports (`gdunit/`) and its console (`gdunit.txt`) go under `<dir>` (`Report:` / `bundle:` lines print the paths) and
  the run's `LogWatch` follows `<dir>/godot.log` (`--log-file` is consumed by the engine, so it does not change the
  project setting: `test_batch.gd` derives the log from `--out`, and points gdUnit's own log path at it in memory for
  the run). So concurrent runs, and a game being played meanwhile, never share a log (a new process rotates the old
  `user://logs/godot.log`, and `LogWatch` tails by path) or overwrite each other's report. A run without `--out` (the
  editor's GdUnit panel) writes no `report.json` and keeps its failure bundles in `user://test_failures/`. `--report=FILE` also writes the
  run's merged report (results, stray logs) to FILE.
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
  (`kill_probe.gd`, `Kill.kill_targets(t, count)`; `arm_probe.gd`, `Arms.check_lengths(t, c, when)`: both arms keep their length) and `tests/_navigation` (`bake_probe.gd`,
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
