# tools/coverage

Runtime coverage of the game, statement by statement: which `scenes/` code runs in real matches and in the game
tests. It is for refactoring: to find code nothing runs (`dead`), branch arms a live function never takes, code only
the tests reach, and live code no test pins. It reads what *ran*; `tools/audit_scan.py` stays the view of what is
*referenced*, and the report uses both.

The tool is not part of the game. It lives only in `tools/coverage/` and `tools/coverage.py`, works on a throwaway
copy of the repo, and never touches the real tree: the `coverage_isolation` lint rule (`tools/lint_rules/`) fails if
`scenes/`, `tests/`, `addons/` or `project.godot` ever name it. Delete the two and nothing else breaks.

## Commands

```sh
python3 tools/coverage.py run                    # 24 real matches, 2 at a time, and their report.md
python3 tools/coverage.py run --tests --jobs=auto  # the game tests, with the statements each test ran
python3 tools/coverage.py report                 # both, combined, for HEAD
python3 tools/coverage.py report --domain=ai     # one domain
```

Run `run` with the Bash sandbox disabled: it starts Godot (found as `tools/run_tests.sh` finds it: `GODOT`, then
`godot` / `godot4` on PATH, then `/Applications/Godot*.app`).

| Command | What it does |
|---|---|
| `instrument` | Builds an instrumented copy in `artifacts/tmp/` (below) and prints its path as the last line. The probe stays idle in it (no `FE_COVERAGE`), so the copy loads, lints and runs its tests like the game. The copy is kept: no run sweeps it. Delete it when done; the next copy made removes the `user://` folder it leaves behind. |
| `run [--matches=24] [--jobs=2] [--seed=N] [--endless-every=4] [--windowed] [--keep]` | Plays real matches in a fresh instrumented copy and writes a run folder (below). |
| `run --uninstrumented [--matches=N] [--jobs=N] [--seed=N] [--endless-every=N] [--windowed]` | Plays the same matches in a copy that has the probe (it still starts, caps and records each match) but no counter bump, and writes `artifacts/coverage/<sha>-<time>-uninstrumented/` (`meta.json`, `hits.json` with empty counts, an empty `map.json`, no report). It is the baseline for the counters' cost and for whether they change what a match does: compare its `meta.json` `matches` with a measured run's over the same `--seed`. `report` never reads it. |
| `run --tests [run_tests.sh args...] [--keep]` | Runs the copy's own `tools/run_tests.sh --no-lint --skip-domain=perf` plus the args (`--jobs=`, `--domain=`, ...), after linting the copy with its own `tools/lint.sh --skip-rule=coverage_isolation --no-gdstyle` (the copy names `CoverageProbe` on purpose, and each probe shares its statement's line, which gdstyle would reflow, so line numbers match the real tree). It measures coverage and does not judge the tests: every selected test runs, and one that fails or times out in the copy is recorded in `meta.json` (`failed`), listed in the report and printed, its hits kept like any test's (a wall-clock budget, such as `audio/bank`'s, fails from the counters' cost alone). It exits 0 when `run_tests.sh` finished (printed its summary line) and the hits merged, whatever the tests' verdicts; it fails only when the run itself broke: a lint failure, the runner exiting non-zero with no hits or before its summary line, a probe hook missing, or the repo changed. |
| `report [--domain=x] [--run=DIR...] [--out=DIR]` | Prints the Markdown report of the newest matches run and the newest tests run of HEAD under `artifacts/coverage/`, or of the run folders given, naming the folders it combined (several matches runs read as one run of all their matches, in seed order). `--out` also saves it into that folder: `report.md`, `report.json` and `runs.json` (each folder combined: `folder`, `source`, `commit`, `time`, `units`); a folder that already holds a `report.md` is refused, never overwritten. |

`run` (matches):

- `--matches=N`: the game processes to play. Process *i* plays seed `N0+i` in **Watch** mode, both sides the same
  size, cycled 1v1..5v5 by the seed (`seed % 5 + 1`). Every `--endless-every`-th process (default 4; 0 = none)
  plays an **Endless** run of three matches instead, which covers the teardown between matches and Main's
  randomising. `--seed=N0` pins the base seed; without it the base is random, and recorded.
- `--jobs=2`: processes at a time, 2 when not given; a positive number, or `auto` (the core count, at most 6). All of
  them share one Von server, and that server is the limit, not the cores: one match keeps Von at up to 7-9 cores in
  bursts (measured on a 12-core machine), so more games than it can answer make it time walks out, and those NPCs hold
  steady and the matches run to the cap. On that machine `--jobs=auto` (6) starved it even when nothing else ran (93 %
  of walks failed, 31 of 36 matches under the floor). **Picking `--jobs`:** start low (1 or 2) on a quiet machine and
  keep the largest value whose run prints no Von guard `WARNING`; a warning means lower it and run again. The guard is
  the arbiter, not the load. Measured there at c8821b0: `--jobs=2` started on a quiet machine kept every match above
  the floor (36 matches in 6 chunks of 4 processes, 9.1-35.7 decided per NPC per game minute, against a median 15.5 at
  `--jobs=1`), short test runs from other worktrees meanwhile included; under another worktree's sustained 6-process
  test suite the same `--jobs=2` starved (0.8 and 1.3, raw idle 13 %). Hence the default of 2: start it on a quiet
  machine, in chunks (below) when quiet stretches are short.
- `--windowed`: play with a window instead of headless (recorded in `meta.json`). Not needed to measure drawing:
  headless Godot still calls `_draw` and so runs the pixel-art painters (measured at c8821b0, twice over 36 headless
  matches: all 58 functions of `scenes/art/` ran, 57 or all of them in every match, 25 of the 28 `_draw` methods ran;
  the 3 that did not, and the painters that did not, draw what a Watch match never shows: the human's order and stack
  markers, vehicles, the debug overlays, the defenders' grenades). Headless only skips the GPU's part (shaders, the
  render itself).
- `--keep`: keep the instrumented copy and the raw per-process hit files in `artifacts/tmp/` (their paths are
  printed); no later run sweeps them, so delete them by hand when done.
- **Von guard:** each match records how often its NPCs got a Von decision (`decided_per_npc_minute`: walks Von
  answered, below). A match under `runner.VON_DECISIONS_FLOOR` (half the rate of quiet `--jobs=1` matches;
  `von_floor` in `meta.json`) had its NPCs starved of decisions, by a Von server busy for other worktrees or too many
  game processes for it: its walks timed out, its NPCs held steady and such a match tends to run to the cap, so its
  coverage is not a normal match's. The walks *started* do not show it (they go on at the decide cadence, answered
  or not); the decided ones do. `run` then prints a `WARNING` naming those matches (`<seed>-<match>`, their rate and
  failed share) and the report's header repeats it; the run still exits 0 and never lowers `--jobs` itself:
  re-run with fewer jobs, or when the machine is quiet.
- **Exit code:** 0 unless the run itself broke or hits were lost: a process killed over its wall-time limit, a probe
  hook missing, a seed with no hits, a game process that exited non-zero before its final flush (the hits after its
  last flush are lost), or the repo changed. A game process that exits non-zero *after* its final flush (its hit
  file marked `final` and holding every match it was planned, each decided) lost nothing: Godot can still abort in
  its own shutdown, after the tree is freed (seen on this machine: `libc++abi: ... recursive_mutex lock failed`).
  It is recorded in `meta.json` (`crashed`), listed in the report and printed, its logs are kept in the run folder's
  `crashed/`, its hits count like any match's, and the run exits 0.

## How a run works

1. `workspace.py` copies the repo into `artifacts/tmp/fe-coverage-copy.<pid>.<random>/` and makes the run's hit
   folder beside it (`artifacts/tmp/fe-coverage-hits.<pid>.<random>/`, below): the tracked files, the untracked ones
   git does not ignore, and `.godot/` (the import cache). No `.git`, no ignored file, nothing of `artifacts/`.
2. `instrument.py` puts a counter bump on the same line, before every statement of `scenes/**/*.gd`
   (`CoverageProbe.h[7] += 1; <statement>`), so a line in the map, in the copy and in an engine error are the same
   line. It copies `probe.gd` in as `tools/coverage/coverage_probe.gd`, registers it **first** in the copy's
   `[autoload]` as `CoverageProbe`, gives the copy a `user://` folder of its own (so a run never writes the
   developer's `settings.json` or Von log), and writes the statement map. `scanner.py` finds the statements from
   indentation and brackets; what it is not sure of is left untouched and listed as **uninstrumented**.
3. The Von decision server: one already answering on port 8000 is reused and left running; otherwise the run starts
   the copy's `application/von/server_path` and stops it afterwards. With neither, the NPCs hold steady and every
   match runs to the cap (the run says so).
4. Each game process gets `FE_COVERAGE`, the path of its run config. The probe then:
   - **matches**: starts the match by emitting the setup window's `start_requested(config)`, as a click would (so the
     start still waits for Von), ends the match's unit at the MatchHUD's `match_ended(verdict)`, and caps a match
     0.25 game seconds past Main's `endless_time_limit` (verdict `TIME CAP`). It quits after its last match. A
     match is timed from its **world**, the node Main adds to the group `match_world` as it builds the match (in
     the frame the MatchHUD's own clock starts): the wait for Von and the pause between Endless matches are in no
     match's duration, and the cap counts the match itself, so an Endless match is called by Main's own draw at
     the limit, not cut short. A match that ends before its world appeared fails the process;
   - **tests**: the tests run in gdUnit4's game test suites (`scenes/testing/game_test_suite.gd`), each in the group
     `game_test_suites` while gdUnit runs it; the probe follows the newest suite to join the tree and reads its current
     entry (`open_entry`) and its test's context (`open_ctx`, a TestContext:
     `is_finished` and the signal `finished`), duck-typed, every frame and whenever a node is added, and keeps each
     test's hits apart. A test's unit runs from when the probe sees its context open (at the latest as the suite
     adds the test's world) to the context's `finished`, the test's verdict, which the probe hears before the suite
     does. The hits made while no test runs (the process's start-up, each test's teardown after its verdict, the next
     test's start until its context is open) go to one `outside` unit, so code that ran is never read as never run
     and no test is charged with it. A test that ends before its context is seen open (a skip, a script error) has
     no unit, and a suite that listens to `finished` before the probe fails the process (its teardown would be
     charged to the test);
   - writes `coverage_hits_<pid>.json` every 5 s and at exit, atomically, so a crashed or killed process keeps its
     last flush; the last flush, as the tree is freed (after every node's `_exit_tree`), marks the file `final`;
   - fails loudly if a hook it needs is missing (an error in the log, `coverage_failed_<pid>.txt`, exit code 3),
     and the run fails with it. It never records silently.
5. `hits.py` merges the shards; the run writes its folder, then checks that the repo is byte-identical to before
   (`git status` and a hash of `scenes/` + `project.godot`) and fails, naming what changed, if not. A run that fails
   part-way (a probe hook missing, a map mismatch) checks too, and its failure message ends with what changed, or
   says the repo is unchanged.

## Scratch folders and cleanup

Everything a run makes besides its run folder goes in `artifacts/tmp/`, gitignored with the rest of `artifacts/` and
under its `.gdignore` (written before the first copy is made), so neither `git status`, the Godot editor, the lint's
engine pass (`tools/lint_scripts.gd` skips every folder holding a `.gdignore`) nor the repo-wide tools (they walk
`scenes/`, `tests/`, `tools/`, `addons/` and `project.godot` only) see the copy's `scenes/`, which names `CoverageProbe`:

- `fe-coverage-copy.<pid>.<random>/`: the instrumented copy. Its Godot `user://` folder stays where Godot puts it
  (`fe-coverage/<copy name>` under the OS data folder) and is removed with it. Every process the run starts in the
  copy gets `GIT_CEILING_DIRECTORIES` at `artifacts/tmp/` and no `GIT_*` variable, so git there finds no repo, never
  this one.
- `fe-coverage-hits.<pid>.<random>/`: the run's configs, the shards, the game processes' logs and the Von log.

`<pid>` is the process that made the folder. However a run ends (done, failed, an exception, Ctrl-C, SIGTERM or
SIGHUP), it stops the game processes, the test runner with every Godot it started (its own process group) and a Von
server it started, then removes both folders and `artifacts/tmp/` once that is empty; signals wait while it does. The
first stopping signal starts that cleanup, and every Ctrl-C, SIGTERM or SIGHUP after it is ignored until the cleanup
is done. Each process is recorded for the cleanup as it starts (signals wait in between), so none is left running.
Interrupted, it exits 128 + the signal (130 for Ctrl-C, 143 for SIGTERM). A folder its cleanup cannot remove is named
in a warning, and the run's result stands. `--keep` (and `instrument`) mark the folders kept instead. A run killed with
SIGKILL cannot clean up: the next copy or hit folder made sweeps every folder in `artifacts/tmp/` whose `<pid>` is
gone, never one whose process is alive (this run's or another's) and never a kept one. `workspace.cleanup` refuses to
delete anything but a direct child of the repo's `artifacts/tmp/` named as above, and never a symlink. The sweep never
follows a symlink: one named as above, its `<pid>` gone, is removed alone. `artifacts/` or `artifacts/tmp/` may be a
symlink (to another disk, say): the folders are made, and removed, where it points, and the symlink stays.

## Run folder

`artifacts/coverage/<sha>-<time>-<matches|tests>/` (all of `artifacts/` is gitignored, the `.gdignore` a run writes
there included, so Godot never imports it and `git status` never shows it):

| File | Holds |
|---|---|
| `map.json` | the statement map the run was instrumented with (format below) |
| `hits.json` | the merged hit file (format below) |
| `meta.json` | `commit` (HEAD), `time`, `source`, `instrumented` (false for a `--uninstrumented` run), `scenes_hash` (scenes/ + project.godot), `map_hash`, `windowed`, `dirty` (scenes/ or project.godot had uncommitted changes); for matches `seeds` (process order) and `matches` (one per match unit: `seed`, `mode`, `match`, `verdict`, `duration` in game seconds, `shots`, `deaths`, `wall`, `frames`, `physics_peak_ms`, `process_peak_ms`, `npcs`, `decisions`, `decided`, `failed`, `decided_per_npc_minute`, `von_failed_share`, as in the hit file) `von_floor` (the Von guard's floor it was checked against) and `crashed` (the game processes that exited non-zero after their final flush, no hit lost: `seed`, `mode`, `process` (plan index), `pid`, `exit` (the exit code; -6 is an abort), `phase` (`after the last flush`), `log` (its `godot_<i>.out`, stdout and stderr, kept under `crashed/` in the run folder with its `godot_<i>.log`) and `message` (the last line it printed)); for tests the `args`, `run_tests_exit` (`run_tests.sh`'s exit code) and `failed` (the tests that failed or timed out in the copy, in order: `id`, `verdict` `FAIL` or `TIMEOUT`, `first` its first failed check, `""` when it printed none) |
| `report.md`, `report.json` | the report of this run alone (`coverage.py report` combines runs) |
| `crashed/` | the logs of the game processes in `meta.json`'s `crashed` (only when there are any) |

## Report

Rolled up domain → file → function. A function is measured at its first body statement (its `function`
statement); a lambda counts as part of the function it is written in.

| Column | Meaning |
|---|---|
| line | the function's first body line |
| match hits | its hits over every match |
| matches | how many matches it ran in (of the `N` in the header) |
| test hits | its hits over every test, then `(+N outside tests)`: its hits while no test ran (they count as run, but pin nothing) |
| tests | how many tests ran it, with up to three ids: the tests that pin it |
| tags | below |
| uncovered | the line ranges of its statements no run reached (a range runs on until a statement with hits) |
| dead branches | the lines of its branch arms that never ran, in a function that did |

| Tag | When |
|---|---|
| `dead` | no hits anywhere, and nothing references it (`audit_scan.py dead`) |
| `dead branch` | a branch arm (`if` / `elif` / `else` body, `match` arm, loop body) with no hits in a function with hits |
| `test-only` | hits in tests, none in matches (needs a matches run) |
| `untriggered system` | no hits anywhere, but referenced: wired, never triggered in the sample |
| `rare` | ran in fewer than 10% of the matches |
| `live-but-unpinned` | hits in matches, none in tests (needs a tests run) |
| `noise` | `scenes/testing/` and `scenes/ui/testing/`, the dev command server, the debug overlays, the settings menu: tagged, never hidden |

The header warns about the matches of a run under its Von floor (above). Then five sections: **saturation** (per added match, in seed order then match number, over every matches run combined (a run plays its
processes in seed order, so one run reads as played, and one played in chunks reads as one run): the functions and lines no earlier match
ran; a tail of zeros means more of the same matches will not find new code), **failed under instrumentation**
(each test of `meta.json`'s `failed`, with its verdict and first failed check, and the note that a wall-clock
budget fails from the counters' cost), **crashed after the last flush** (each process of a matches run's
`crashed`: its seed, exit code, phase, last printed line and log), **uninstrumented** (each span as
`file:line` with its reason) and **limits**.

**One run in chunks:** when the machine has no quiet window long enough for the whole run, play it as several
runs over consecutive seeds, `run --matches=K --seed=B`, `--seed=B+K`, `--seed=B+2K`, ..., with K a multiple of
`--endless-every` (4 by default), so each chunk's every-4th Endless process falls on the same seed as in one run of
all of them (process *i* of a chunk is Endless when `i % endless-every == endless-every - 1`; a chunk of 2 never plays
one). Then `report --run=<each chunk> --run=<tests run>`: the matches of every matches run are summed and taken in seed
order, so the tags, the matches counts and the curve are those of the one run; the header warns when runs repeat a
match (a discarded chunk passed with its redo). Redo only a chunk that was discarded.

Runs are joined by statement id. Runs instrumented with different maps (different builds) are joined by
(file, line, kind) instead, with a warning; runs of different commits are warned about, naming both.

## Limits

- Zero hits means "did not run in the sampled matches" (or tests), not unreachable.
- Coverage is per statement: the conditions inside one expression (`a and b`, a ternary) are not seen.
- Matches with no human player skip player-only code (input, the leader's command menu, driving a vehicle by hand);
  scripted play through gcmd can cover it.
- Declarations and data (a `const`, a signal, a config field, an unselected data-table entry), shaders, scene wiring,
  gcmd `Expression` eval and runtime-built scripts are not measured; `audit_scan.py` remains the view for
  declarations.
- Counts from threads (the nav bake, the WorkerThreadPool) may lose increments; zero vs. non-zero stays right.
- A result belongs to one commit: re-measure after a refactor.
- `dead` vs. `untriggered system` rests on token matching: a same-named function anywhere hides a dead one.
- Only a process's first match is reproducible by seed: an Endless run's later matches draw theirs at random.

## Modules

| Module | Job |
|---|---|
| `workspace.py` | the copy and the hit folder in `artifacts/tmp/`, tree hashes, cleanup and the sweep of leftovers |
| `scanner.py` | GDScript text to statements and uninstrumented spans |
| `instrument.py` | writes the markers, the autoload and the map |
| `probe.gd` | the template copied in as `CoverageProbe` |
| `runner.py` | the match and test drivers, sharding, Von, the run folder |
| `hits.py` | the hit file format, merge, atomic writes |
| `report.py` | rollup, tags, curve, Markdown and JSON |
| `static_refs.py` | thin adapter over `audit_scan` |

`tools/coverage.py` is the CLI only.

Tests: `python3 -m unittest discover -s tools -t .` (every tool test; the pre-commit hook runs it when `tools/` is
staged), or `python3 -m unittest tools.coverage.tests.test_runner_cli` for one file. The Godot ones are skipped when
there is no Godot binary; `FE_SLOW_TESTS=1` adds the real-tree run (`test_isolation_run.py`, needs Von) and the
windowed run.

## Formats

The modules talk only through two files: the **statement map** and the **hit file**. Both are UTF-8 JSON objects
with a `format` name and a `version`; a reader refuses a file whose `format` or `version` it does not know.
`tools/coverage/tests/` pins both down (`test_instrument.py` the map, `test_hits.py` the hit file).

### Statement map (`map.json`)

Written by `instrument.py` into the instrumented copy, and copied into every run folder
(`artifacts/coverage/<sha>-<time>-<matches|tests>/map.json`) so its hits can be read later.

```json
{
  "format": "fe-coverage-map",
  "version": 1,
  "hash": "9f2c…",
  "statements": [
    { "id": 0, "file": "scenes/main.gd", "line": 20, "kind": "function",  "function": "_ready", "class": "" },
    { "id": 1, "file": "scenes/main.gd", "line": 21, "kind": "statement", "function": "_ready", "class": "" },
    { "id": 2, "file": "scenes/main.gd", "line": 23, "kind": "branch",    "function": "_ready", "class": "" }
  ],
  "uninstrumented": [
    { "file": "scenes/constructs/unsure.gd", "line": 10, "end_line": 10,
      "reason": "a statement starts on the closing line of a multi-line string" }
  ]
}
```

- `hash`: a content hash of `statements` and `uninstrumented` (hex). The same sources always give the same map and
  the same hash; any change to a statement's file, line, kind, function or class changes it. Hit files and
  `meta.json` record it as `map_hash`.
- `statements[i].id == i`: ids are dense from 0, and the id is the index of the probe's counter for that statement.
- `file`: the repo-relative POSIX path of a `scenes/**/*.gd` script.
- `line`: the 1-based source line the statement starts on. The copy keeps every statement on its source line (the
  counter bump goes on the same line, before the statement), so a line here, in the copy and in an engine error
  are the same line. A line may hold several statements (`a = 1; b = 2`, `if c: x`, a lambda inside a call's
  arguments): each has its own id.
- `kind`:
  - `function`: the first statement of a function's body (a method, a `static func`, an inner class's method). Its
    hits are the function's hits.
  - `branch`: the first statement of an `if` / `elif` / `else` body, a `match` arm, or a `for` / `while` body.
  - `statement`: every other statement inside a function body. A lambda's statements count as statements of the
    function it is written in; a lambda is not a function of its own.
  Only statements inside function bodies are measured: declarations (`var`, `const`, `signal`, `enum`, `class`,
  annotations) are not statements.
- `function`: the name of the function the statement is in.
- `class`: the inner class the function belongs to, dotted when nested (`Counter.Nested`); `""` for the script's own
  class.
- `uninstrumented`: spans the scanner was not sure about and left untouched (`line`..`end_line`, inclusive, with a
  `reason`). They hold no statement ids, so they are never read as dead; the report lists them in their own section.

### Hit file (`coverage_hits_<pid>.json` per process, `hits.json` merged)

The probe writes one per game process into the run's hit folder (`artifacts/tmp/fe-coverage-hits.<pid>.<random>/`);
`hits.py` merges a run's shards into the run folder's `hits.json`, which has the same shape.

```json
{
  "format": "fe-coverage-hits",
  "version": 1,
  "map_hash": "9f2c…",
  "source": "matches",
  "final": true,
  "units": [
    { "id": "100-1", "seed": 100, "mode": "watch", "match": 1, "verdict": "DEFENDER WINS", "duration": 41.5,
      "counts": { "0": 1, "1": 1, "7": 312 } },
    { "id": "103-1", "seed": 103, "mode": "endless", "match": 1, "verdict": "TIME UP - DRAW", "duration": 180.0,
      "counts": { "0": 1, "9": 4 } }
  ]
}
```

- `source`: `matches` (a `coverage.py run`) or `tests` (a `coverage.py run --tests`).
- `final` (per-process files only): true in the probe's last flush, written as the tree is freed after every node's
  `_exit_tree`; false in every flush before. A process that exited non-zero with a final file holding all its
  matches lost no hit.
- `units`: what the hits are kept apart by, in the order they were played (a run's merged `hits.json`: process
  order, which is seed order).
  - For `matches`, one unit per match. `seed` the process's seed, `mode` `watch` or `endless`, `match` its 1-based
    number within the process (an Endless process plays three), `verdict` the MatchHUD's `match_ended` text, and
    `duration` its length in game seconds, from its world on (above). `id` is `<seed>-<match>`. A decided or capped
    match also records its outcome and its cost, from its world on too: `shots` (the EventBus autoload's `shot` posts during it; null when the game has no
    EventBus), `deaths` (the nodes of the group `characters` whose `is_dead` is true as it ends; null when the group
    is empty), `wall` (real seconds),
    `frames` (process frames), and `physics_peak_ms` / `process_peak_ms` (the engine's `TIME_PHYSICS_PROCESS` and
    `TIME_PROCESS` monitors averaged over its physics and process frames; the engine sets each monitor once a second
    to the slowest frame of that second, so these are a second's typical worst step, not the mean step: a game whose
    frames take 1 ms and 25 ms in turn reads about 25, not 13). A match cut short by a
    kill has none of them. The game runs at real speed (no `--fixed-fps`), so the counters' cost shows in the step
    peaks and in `frames / duration` (the frame rate headless reaches), and in `wall / duration` only once a step
    takes longer than a physics tick. And how often its NPCs got a Von decision: `npcs` (the AI controllers, the
    group `npc_controllers`, as it ends; a dead NPC's stays), `decisions` (their `debug_state()` `decisions`, the
    decision walks started, summed), `decided` and `failed` (the walks the decision planners, any node with the
    signals `decided(leaf)` and `failed()`, ended during the match with Von's answer and without one: a timeout or
    a bad pick, after which the NPC holds steady), `decided_per_npc_minute` (decided per NPC per game minute; a dead
    NPC stops deciding and still counts, so a bloody match reads a little low) and `von_failed_share` (failed /
    (decided + failed), null when no walk ended); with no controller, `npcs` is 0 and the others null.
  - For `tests`, a unit per test: `id` is the test id (`ai/entry/entry_waits_for_stack`). And units
    `{ "id": "", "outside": true, "counts": ... }` for the hits made while no test ran (the process's start-up, each
    test's teardown after its verdict); the report counts them as run (so neither `dead` nor `untriggered system`) and
    never as a test that pins a function. A process's own file may hold several units of one id: an `outside` unit
    for each stretch between tests, and a unit for each run of a test it repeats (`run_tests.sh --repeat=N`). The
    merge sums units that share an id, so `hits.json` holds one unit per test and one `outside` unit.
- `counts`: sparse. Each key is a statement id as a decimal string, and its value is the hits (> 0) during that unit.
  A missing id means 0 hits.
- **Merge** (`hits.merge`): every file must have the same `map_hash` and `source`, or the merge refuses. Units are
  concatenated. Units that share an `id` have their counts summed and keep the other fields of the first. So a
  run's totals are the same however its matches were spread over processes.
- **Writes are atomic**: written to a temporary file in the same directory, then renamed over the old one, so a
  reader never sees half a file. The probe flushes every 5 s and at exit, so a process killed with `kill -9` leaves
  its last flush.
