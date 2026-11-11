# Runner flags: what the header of `tools/run_tests.sh` leaves out

The header lists every flag; this file holds the rules and the reasons behind them.

- **Per-run output dir:** every process gets a fresh `mktemp -d` (`--log-file <dir>/godot.log`, `--out=<dir>`). The
  report, failure bundles, shots, gdUnit's reports (`gdunit/`) and its console (`gdunit.txt`) go there, and `LogWatch`
  follows that `godot.log` (`test_batch.gd` derives it from `--out`), so concurrent runs and a game played meanwhile never
  share a log (the shared `user://logs/godot.log` is written by every start and never read: `log-gate.md`) or overwrite a
  report. A run without `--out` (the GdUnit panel) writes no `report.json` and keeps bundles in `user://test_failures/`.
- **Jobs:** the whole suite runs on `--jobs=auto`; any selection (words, `--id`, `--domain`, `--failed`, `--repeat`) runs
  one process, since a process costs about 3 s to start and filter words load every test script to match (about 10 s
  more). `--jobs` never starts more processes than the `--id` list has ids, and is not used with
  `--list` / `--self-test`; `--windowed`, and `--shots` without `--jobs`, run in one process (`_a` / `_b` restore pairs).
- **Shards are balanced by measured cost:** the wrapper keeps each test's wall-clock ms in
  `$TMPDIR/example_godot_costs_<checkout hash>.json` (rewritten after all shards finish; none yet: the declared
  `timeout`; an unmeasured id: the median) and passes `--costs=<file>`. A live Von test and the native suites stay in shard 0; a replayed one is dealt by cost.
- **The Godot slot pool:** every godot test process the wrapper starts (shard, perf phase, `--repeat` native rerun,
  `--base`, `--list`, `--self-test`, the first import) holds one of `max(1, cores / 2)` machine-wide slots (lock files
  `slot<i>.lock` in `$TMPDIR/forced-entry-godot-slots`, `GAME_TEST_SLOT_DIR` names another). `tools/godot_slot.py`
  takes the slot and becomes the godot command, so the process holds the `flock` and the slot frees when it exits however
  it ends (a dead pid's lock is reclaimed). Runs in other worktrees and the pre-commit hook therefore share the CPU.
  `auto` = the free slots, at least 1; `--jobs=N` keeps N shards, each waiting for its slot ("waiting for a Godot slot").
  `GAME_TEST_JOBS=N` caps the jobs of every run in a process tree. The lint's engine pass, editors and played games take
  no slot. `python3 tools/godot_slot.py status` prints `<taken> <size>`, `free` the free count.
- **Perf after the shards:** with more than one process, perf tests are held back and run alone in one process after
  every shard ends, then folded into the combined summary and `--failed` report. With one process (a selection,
  `--windowed`, perf alone) nothing is held back. Perf budgets are wall-clock ms about 4x their baseline.
- **`--quiet[=MINUTES]`** (the rule lives here): before a process that holds perf tests starts, the wrapper waits until no
  other Godot is busy and the 1-minute load is under `max_load` in `tools/perf_quiet.conf`. A Godot is an engine process
  (an editor, a test run, a game; not a `godot-mcp` server, which is node) that burned at least `busy_cpu` percent of a
  core (50) over a `busy_sample_s`-second sample (2), both in the conf; an idle editor does not count, and what the run's
  own wrapper started never does. A run that starts just after the gate clears is seen only at the next poll. A process holds perf
  tests when it is the perf phase of a sharded run, the one process of a run whose selection holds perf (the whole suite
  on one job, perf alone, `--id=perf/x,ai/y`), or a `--repeat` rerun of a `tests/perf` native suite. Filter words hold
  one only if a `--list <words> --domain=perf` engine start lists a perf test. After `MINUTES` (default `timeout_min`) it
  runs anyway and marks that process's results `loaded`: a `loaded` result is no evidence of a regression. An unreadable
  `perf_quiet.conf` ends the run with exit 2. The wrapper appends `(load <x>, <n> busy Godot)` to every `PERF` line.
- **Von tests:** a `requires_von` test with a recording runs in every normal run, `--changed`, the pre-commit hook and
  `--base` included, from `<name>_test.von.json` beside it (`VonRecording`; entries keyed by state + question + sorted
  option descriptions, ids normalised to spawn order). Each answer lands 12 physics frames after its ask, as live does, so
  record, live and replay play the same frames. No server, no pacing, sharded like any test. An ask the recording lacks, or
  a missing or unreadable file, FAILs naming the question and `tools/run_tests.sh --record-von --id=<id>`: a wording change
  in a snapshot or a question makes recordings stale; run that command (it needs a live Von on :8000) and commit the diff.
  - `--record-von` runs the selected Von tests live and writes each passing test's recording whole (unused entries drop);
    FAILs with no server, like `--require-von`. `--include-von` and `--require-von` run live and never read or write a
    recording. Live and record runs are paced in real time and kept in shard 0.
  - **Live-only** (`"live_only": true`, with `requires_von`): tests of the transport or the gate
    (`ai/decision/von_request_across_pause`, `_harness/von_probe`) and one a replay cannot reproduce,
    `ai/investigate/defenders_stay_in_house_quiet_von` (a 40 s generated-house match whose fight moves the NPCs by a
    hair differently in a replay). They never replay and are skipped without a server (FAIL under `--require-von`).
  - **Own process** (`"own_process": true`; a last resort and a debt: needs a follow-up ticket): the wrapper leaves
    the test out of the shards (`--skip-own-process`; ids go to `<out>/own_process.txt`) and runs it after them in an
    engine process of its own, once per `--repeat` (`--fail-fast` stops at the first failure), its report merged in. The
    engine orders the contacts of touching rigid bodies by allocation slots, which follow what the process ran
    before, so a replay whose snapshot wording turns on such a piece at a band edge matches its recording only in a
    fresh process. Only `ai/grenade/combat_frag_take_cover` has it (20 of 20 fresh-process replays pass). Only
    `run_tests.sh` honours it: the browser, the GdUnit panel and a direct batch run use the shared process.
  - A Von test with no recording FAILs naming `tools/run_tests.sh --record-von --id=<id>`; record a new one in its commit.
  - The totals line counts only the Von tests not run: `N skipped (V need Von, not run: --require-von)` (live-only,
    or a live run with no server). `--changed` ends with `NOTE <n> Von test(s) in the changed domains were not run:
    tools/run_tests.sh --domain=<d> --require-von` when it skipped any. `--record-von` skips a live-only test. `--list` marks each `von:replay`, `von:live-only` or `von:unrecorded` (no file: it FAILs).
- **`--base=<rev>`:** the working tree's tests against `<rev>`'s code, in a temporary `git worktree` under `$TMPDIR` that
  gets the working tree's `tests/` whole (`.uid` files and helper folders included). It is removed also on ^C or a kill
  of the wrapper (`tools/godot_slot.py stop` ends the engines first). The working tree is never written, no lint. Combinations
  it refuses are in the `tools/run_tests.sh` usage. `fix` uses it to show a changed regression test still red on the old code.
- **Other flags:** `--skip-domain` wins over every other selection, `--changed`'s included. `--repeat=N` reruns a native
  suite in N-1 processes of its own (with a hand-given `--shard` it runs once). Options take the `--name=value` form; any
  other `--` argument exits 2 with `unknown flag: <arg>`: the wrapper forwards only its `BATCH_FLAGS`, and
  `tools/tests/test_run_tests_flags.py` checks that every flag the batch reads is forwarded.
- **Test seams** (set only by `tools/test_log_gate.py` and the tool tests): `GAME_TEST_SLOT_POLL`, `GAME_TEST_QUIET_MINUTE`,
  `GAME_TEST_QUIET_POLL`, `GAME_TEST_STOP_WAIT` and `GAME_TEST_VON_PORT` (the port probed for a live Von server, 8000).

## `--changed`

`runner-flags-changed.md`: how a changed file or a changed spec paragraph maps to tests.
