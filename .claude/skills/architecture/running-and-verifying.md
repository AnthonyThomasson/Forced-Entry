## Running & verifying

- Main scene `res://scenes/main.tscn`.
- **Worktree editor:** `tools/editor.sh [--autorun]` opens a Godot editor on the checkout, named after the
  worktree directory (`GAME_TICKET`; Main passes it as `ticket` to the setup window, which shows it on top;
  a `--ticket=` user arg overrides it, and a run from any editor falls back to the directory name), unless
  one is already open there (it then prints that editor's pid, port and log). Each gets its own free
  command-server port (`GODOT_CMD_PORT`), importing first in a fresh worktree. `--autorun`
  makes the editor plugin `addons/ticket_autorun/` press Play once it is up.
- **The change's tests in a window:** `tools/play_tests.sh [ids…]` opens a game window on the checkout that plays the
  tests the change added or modified (since the merge-base with `origin/main`) one after another, for a person to
  watch; `show-me` runs it, `domain-testing` has the detail.
- **Verification ladder** — use the cheapest rung that proves the change:
  1. **Loads?** `godot-run` skill: headless load check (`tools/load_check.sh --import` when you add a `class_name` or a script).
     **Clean?** `tools/lint.sh [paths]` (about 14 s for the whole tree, nearly all of it the engine pass) prints every GDScript analyzer warning of the editor's
     Debugger > Errors tab (unused variable, integer division, shadowed names ...) per file, then every project lint rule
     (`tools/lint_rules/`, one section each), then gdstyle's two (`gdstyle fmt --check`: a script the formatter would change;
     `gdstyle check`: the rules `gdstyle.toml` turns on, among them lines over 100 columns and member order, and of its
     `quality/*` rules 18, at gdstyle's default thresholds: `unnecessary-pass`, `self-comparison`, `duplicate-dict-key`,
     `duplicated-load`, `max-inner-classes`, `no-self-assign`, `unreachable-code`, `no-else-return`, the function-level
     `max-function-length`, `max-parameters`, `type-hint`, `max-nesting-depth`, `max-returns`, `max-branches` and
     `max-local-variables`, and the structural `max-file-length`, `max-class-variables` and `max-public-methods`; five
     are off by decision (`no-debug-print`, `await-in-loop`, `empty-function`, `allocation-in-loop`, `process-get-node`;
     the reasons beside them in `gdstyle.toml`));
     any finding fails it, and it runs first in every
     `run_tests.sh` and fails the run before a test starts. `tools/gdstyle.sh fmt PATH` formats a script. Fix the code;
     never silence a warning (`audit`).
  2. **Behaves?** `tools/run_tests.sh [words]` runs every test headless and deterministically through gdUnit4's command-line
     tool: the simulation tests (`tests/**/*_test.gd`, `GameTest`s, through their folder's wrapper suite) and the native
     pure-logic suites (`*_suite.gd` extending `UnitSuite`)
     (exit 1 on a lint finding, a failure, or any engine error/warning logged during a test). Useful flags: `--list`,
     `--changed` (the domains your uncommitted changes can break, in one run), `--id=<id>` / `--domain=a,b`
     (exact selection), `--failed` (rerun last run's failures), `--jobs=auto` (parallel shards),
     `--fail-fast`, `--summary` (failures + totals only), `--repeat=N` (flaky check), `--seed=N`,
     `--no-lint`, `--json`, `--report=FILE`, `--include-von` / `--require-von`. A failure prints actor state and a `bundle:` JSON path;
     each run's output dir also holds gdUnit's JUnit `results.xml` and HTML report.
     Writing tests: `domain-testing` skill; debugging one: `test-debug` skill. In the game, the setup
     window's **Tests** button opens the browser to play one; in the editor, the GdUnit panel runs one case, a suite or
     everything (`domain-testing`, "The GdUnit panel").
  3. **Exploratory / not yet scriptable?** `godot-run` skill: drive the live game through the dev
     command server (`tools/gcmd.py`).
  4. **Whole-AI outcomes?** `tools/match.py` scores full defender-vs-invader matches.
  **Fast enough?** `tools/run_tests.sh --domain=perf`: the performance tests (`tests/perf/`: thirteen guards) hold a 5v5 and a 10v10 match, each built through `MatchBuilder` as Main builds one (its squads following their leaders, the sides in contact before the window), to one 60 fps
  frame on average and hold stress cases to their budgets: automatic fire, nav re-bakes and path queries, a whole match dying in one
  frame, an ambush order's posts laid for a crew, a furniture pile shoved at once, house generation, the sound library's render, hundreds of hits on one body, an NPC crowd, grenades thrown into a 5v5 and a
  frag and a stun bursting in a crowded room (`domain-testing` skill, "Performance tests"); a change to a per-frame path should leave them
  green, but for the 10v10's p95 and max, red on a quiet machine until #98 (an invader's decision weighing its grenades). Headless they measure the CPU; `tools/run_tests.sh --windowed` measures the render too.
  **What runs?** `tools/coverage/README.md`: a dev tool outside the game, kept out of it by the `coverage_isolation` lint rule.
  A bugfix starts with a failing test on rung 2 (`fix` skill).
- The relevant **`domain-<name>` skill** documents each domain's behaviour to verify (house
  generation, movement/pushing, items, interactions, combat).
