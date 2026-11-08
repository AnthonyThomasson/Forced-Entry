# Running and verifying

Main scene: `res://scenes/main.tscn`. Each tool's header (or `--help`) holds its flags.

- **Worktree editor:** `tools/editor.sh [--autorun]` opens a Godot editor on the checkout, named after the worktree directory (`GAME_TICKET`, shown atop the setup window), unless one is already open there (it prints that editor's pid, port and log). Each editor gets its own command-server port (`GODOT_CMD_PORT`). `--autorun` makes `addons/ticket_autorun/` press Play.
- **The change's tests in a window:** `tools/play_tests.sh [ids…]` plays the tests the change added or modified (since the merge-base with `origin/main`) one after another, for a person to watch. `show-me` runs it.

## The verification ladder

Use the cheapest rung that proves the change.

1. **Loads and lints.** `godot-run` skill: `tools/load_check.sh --import` (after adding a `class_name` or a script) and `tools/lint.sh [paths]`. Lint = the engine analyzer, the project rules (`tools/lint_rules/`) and gdstyle (`gdstyle.toml`; `tools/gdstyle.sh fmt PATH` formats). Any finding fails it, and `run_tests.sh` runs it first. Fix the code, never silence a warning (`audit`).
2. **Behaves.** `tools/run_tests.sh` runs the game tests (`tests/**/*_test.gd`, through their folder's wrapper suite) and the native suites (`*_suite.gd`) headless and deterministic, through gdUnit4. It fails on a lint finding, a failed assertion or any engine error or warning logged during a test. `--changed` runs the domains your uncommitted changes can break; `--id=` / `--domain=` select; `--failed` reruns the last failures. A failure prints actor state and a `bundle:` JSON path. Writing tests: `domain-testing`; debugging one: `test-debug`. A bugfix starts with a failing test on this rung (`fix`).
3. **Exploratory.** `godot-run` skill: drive the live game through the dev command server (`tools/gcmd.py`).
4. **Whole-AI outcomes.** `tools/match.py` scores full defender-vs-invader matches.

Also:

- **Fast enough?** `tools/run_tests.sh --domain=perf` (`tests/perf/`): a change to a per-frame path should leave them green. Headless they measure the CPU; `--windowed` measures the render too. The pre-commit hook skips perf. Detail: `domain-testing`.
- **What runs?** `tools/coverage/README.md`: a dev tool outside the game, kept out of it by the `coverage_isolation` lint rule (ADR 0001).
- Each `domain-<name>` skill names the behaviour of its domain to verify.
