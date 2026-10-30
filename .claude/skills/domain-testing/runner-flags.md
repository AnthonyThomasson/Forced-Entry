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
  **Without `--jobs`, a run of the whole suite uses `auto` and any selection (filter
  words, `--id`, `--domain`, `--failed`, `--repeat`) one process**, since a process costs about 3 s to start (gdUnit's
  discovery of its suites is 1.2 to 1.9 s of it), and filter words, which load every test script to match it, about 10 s
  more; an explicit
  `--jobs` never starts more processes than the `--id` list has ids. Not used with `--list`/`--self-test`/`--shots`
  (the `_a`/`_b` restore pairs need one process in id order). **Shards are balanced by measured cost:** the wrapper
  keeps each test's wall-clock ms (the mean of the previous and the latest measurement) in
  `$TMPDIR/example_godot_costs_<checkout hash>.json`, rewritten only after all shards have finished, and passes it to
  every shard as `--costs=<file>`; costliest tests go first onto the lightest shard (Von tests all stay in shard 0 and
  weigh it only when they run, and the native suites run only in shard 0). With no costs file (a fresh checkout) it falls back to the declared `timeout`, an
  unmeasured id costs the median. `--fail-fast` stops after the first FAIL/TIMEOUT (per shard).
- **The Godot slot pool:** every godot test process the wrapper starts (a shard, the perf phase, a `--repeat` rerun of the
  native suites, `--base`'s run, `--list`, `--self-test`) holds one slot of a machine-wide pool of `max(1, cores / 2)`
  slots, lock files `slot<i>.lock` in `$TMPDIR/forced-entry-godot-slots` (`GAME_TEST_SLOT_DIR` names another
  directory). `tools/godot_slot.py` takes the slot and becomes the godot command, so the process itself holds the
  `flock` and the slot is free when it exits, however it ends; a lock file whose pid is dead is reclaimed. So runs in
  other worktrees, and the pre-commit hook (which passes `--jobs=auto`), share the CPU. **`auto` = the free slots, at
  most `cores / 2`, at least 1**; `--jobs=N` keeps N shards and each waits for its slot. A process with no free slot waits
  and says so once: `waiting for a Godot slot (<n> of <n> taken)`. `GAME_TEST_JOBS=N` caps the jobs of every run in a
  process tree, `auto` and `--jobs=N` alike (the smaller wins). The lint's engine pass, editors and played games take no
  slot. `python3 tools/godot_slot.py status` prints `<taken> <size>`, `free` the free count (they only look: they take no slot and
  write nothing; takers go one at a time, so two never reclaim the same orphaned lock). A run's header (a wrapper
  line before the first test) and its totals line print the 1-minute load.
- **Perf after the shards:** with more than one process the perf-domain tests are held back from the shards and run after
  every shard has ended, alone in one process (one slot), then folded into the combined summary, totals and `--failed`
  report; `--repeat` applies to that run too. With one process (a selection, `--windowed`, a selection of perf alone)
  nothing is held back. Perf tests budget wall-clock ms about 4x their baseline, so a trip means a loaded machine or a
  slower game (`--quiet`, below).
- **`--quiet[=MINUTES]`:** before a process that holds perf tests starts (the perf phase of a sharded run; the one process of
  a run whose selection holds perf: the whole suite with one job, perf alone, `--id=perf/x,ai/y`; a `--repeat` rerun of a
  native suite of `tests/perf`) the wrapper waits until no other Godot process runs (any godot this run did not start,
  editors and played games included) and the 1-minute load is under `max_load` in `tools/perf_quiet.conf` (6: this box's
  idle baseline is about 5), printing the load and the count of other Godot processes at once and each minute. After
  `MINUTES` (default `timeout_min` of the same file, 30) it runs anyway and marks that process's results `loaded` (on each
  verdict line, `"loaded": true` in `report.json`): a `loaded` result is no evidence of a regression. A gate that fails for
  another reason than its timeout (an unreadable `perf_quiet.conf`) ends the run with exit 2 before a test starts. The
  wrapper appends `(load <x>, <n> other Godot)` to every `PERF` line it passes (shown with `--verbose`), quiet or not.
- **`--base=<rev>`:** the working tree's tests against the code of `<rev>`: a temporary `git worktree` of `<rev>` in
  `$TMPDIR` gets the working tree's `tests/` whole (`.uid` files and helper folders included), is imported, runs the
  selection in one process, prints its lines under `== on base <rev> (<short sha>) ==`, and is removed, also on ^C. The
  working tree is never written; no lint; the exit code is that run's verdict. Refused with exit 2 and a reason line:
  with `--changed`, `--staged` or `--jobs` above 1, and for an unknown `<rev>`. `fix` step 5 uses it
  (`--base=<merge-base> --id=<id>`) to show a changed regression test still red on the old code.
- **Test seams** (set only by `tools/test_log_gate.py` and the tool tests, not by a person): `GAME_TEST_SLOT_POLL`
  (seconds between a waiting process's looks at the pool, 0.5), `GAME_TEST_QUIET_MINUTE` (the seconds a `--quiet` "minute"
  lasts, 60) and `GAME_TEST_QUIET_POLL` (seconds between its looks at the machine, 5), `GAME_TEST_VON_PORT` (the port the
  wrapper probes for a live Von server, 8000) and `GAME_TEST_CHANGED_FILES` (below).
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
  (`kill_probe.gd`, `Kill.kill_targets(t, count)`; `arm_probe.gd`, `Arms.check_lengths(t, c, when)`: both arms keep their length), `tests/_items` (`weapon_style_probe.gd`) and `tests/_navigation` (`bake_probe.gd`,
  `Bake.problem(region)`: what the NavigationServer would refuse in a baked polygon) are unknown to the mapping, so a change to any of them runs the whole suite).
  An edited `tests/<domain>/…_suite.gd` (a wrapper or a native suite) runs that domain.
  `GAME_TEST_CHANGED_FILES` (newline-separated paths) stands in for git's view of the changes, which is how
  `tools/test_log_gate.py` tests this mapping. **A changed `docs/*.md` paragraph runs the tests it names:** the
  blank-line-bounded block of the new file that holds a changed line (a pure deletion: the block around where it was),
  its `Test:` / `Tests:` line (`tools/spec_tests.py`; a paragraph that names none takes the block that begins with a `Tests:`
  line and directly follows it, before the next heading or paragraph of another kind) gives backticked names, each resolved to
  `tests/**/<name>_test.gd` (a name with a `/` is a path under `tests/`; under `--staged` among the files the index holds). Those ids run `--repeat=5` under `== tests named by changed spec
  paragraphs ==`, also when their domain already ran; Von ones get `--include-von` only when a Von server is live
  (otherwise they are skipped and counted by the Von `NOTE`); `--skip-domain` still wins. A changed paragraph with no
  `Test(s):` line prints `NOTE docs/<f>.md:<line>: changed paragraph names no test`, a name with no test file
  `NOTE unknown test name in docs/<f>.md:<line>: <name>`; neither fails the run. **`--changed --staged`** (the pre-commit hook's) maps what is staged
  (`git diff --cached`) instead, and lints what the commit holds through `tools/lint_staged.sh` (the helper the hook's
  own lint runs too): the staged scripts (added, copied, modified or renamed, as they are on disk; the whole tree when
  `project.godot`, a gdstyle file or a file of the lint itself is staged: `tools/lint.sh`, `lint_report.py`,
  `lint_scripts.gd` / `.tscn`, the code of `tools/lint_rules/` but its tests; no lint when no script is), labelling a finding in a script not staged
  `not in this commit: <path>` (`tools/lint_label.py`); that lint never records the clean-lint fingerprint.
  `test_log_gate.py`'s `StagedChangedTests` run it through git in a throwaway repo.
