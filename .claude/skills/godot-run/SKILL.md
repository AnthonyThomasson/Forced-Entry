---
name: godot-run
description: Use after editing GDScript or scenes, before reporting work done, and to run and drive the game live when a test cannot show a change.
---

# Godot run

**Bash sandbox disabled** (`dangerouslyDisableSandbox: true`) for every Godot, `tools/*.sh` and `gcmd.py` command: under the
sandbox Godot busy-spins with no output. Godot is not on PATH; the scripts find it themselves (`GODOT` overrides). For a
direct call:

```bash
GODOT="$( command -v godot || command -v godot4 || ls /Applications/Godot*.app/Contents/MacOS/Godot 2>/dev/null | head -1 )"
```

**Keep logs out of your context:** for a log-heavy run, spawn `Agent` with `model: "haiku"` giving it the worktree root, the
exact commands, the marker lines for success/failure and "sandbox disabled, edit nothing, reply only verdict + up to ~15
matching lines verbatim". Judge the reply yourself; fix or rerun yourself on FAIL or ambiguity.

## 1. Load check and lint

```bash
tools/load_check.sh               # headless: main scene + autoloads, a few frames, quit; flags in its header
tools/load_check.sh --import      # import first (new scripts' .uid files, the class cache), then the check
tools/lint.sh [paths]             # analyzer warnings headless runs never print, the lint rules, gdstyle
tools/gdstyle.sh fmt [paths]      # format scripts the way gdstyle wants them (gdstyle.toml: 100 columns, tabs)
```

- `load_check.sh` exits 1 and prints every engine error or warning in the log; 0 = clean. The verdict comes from the log
  because Godot exits 0 on a parse error. A warning only one renderer logs fails only in that mode: add `--windowed` when a
  change touches rendering.
- `Identifier "Foo" not declared` right after adding `class_name Foo`: stale class cache, run `--import`.
- A new script (a test too) gets its `.gd.uid` only from an import, which headless runs skip: run `--import` and stage the
  `.uid` with the `.gd`. The pre-commit hook refuses a `.gd` under `scenes/`, `tests/`, `addons/` or `sandboxes/` without
  its `.uid`, and a `.uid` without its `.gd`.
- One script: `"$GODOT" --headless --path . --check-only --script scenes/character/character.gd`.
- **Lint:** fix the code; never silence a warning or a finding (`audit`, step 5). It prints a section per pass:
  `== GDScript analyzer (engine) ==`, `== <rule>: <description> ==` per project lint rule (`tools/lint_rules/README.md`),
  `== gdstyle fmt --check ==` (each script the formatter would change, with the `tools/gdstyle.sh fmt <path>` that fixes it)
  and `== gdstyle check ==` (`path:line:col: message [rule]`); each ends in `PASS` or `FAIL`, and any failing section fails
  the lint. `--list-rules`, `--rule=a,b` (those rules only, no engine or gdstyle pass), `--skip-rule=a,b` and `--no-gdstyle`
  select. Every `.gd` outside `addons/`, `.godot/`, `artifacts/` and the coverage tool's fixtures is held to it, `tools/` and
  `sandboxes/` included. `tools/gdstyle.sh` pins the gdstyle version, fetches it on first use into
  `~/.cache/forced-entry-gdstyle` and checks its sha256.
- A clean load only proves it parses. **Prefer a test** for behaviour (`tools/run_tests.sh --changed --summary` imports a
  fresh checkout itself). Drive the live game only to explore or for what a puppet cannot reach; N-match scoring is
  `tools/match.py`.

## 2. Launch

Load check first: never drive a game that doesn't parse.

- Worktree editor: `tools/editor.sh --autorun` (presses Play; `show-me`). It prints `editor pid … | command port <port> | log
  <log>` (`$TMPDIR/editor_<worktree>.log`), or `editor already running` with the same fields. The port is per worktree, so
  pass `--port <port>` to `gcmd.py`.
- Or from Bash: `"$GODOT" --path . --log-file "$TMPDIR/godot_engine.log" > "$TMPDIR/godot_run.log" 2>&1 &` (port
  9080). A test runner start (`res://scenes/testing/test_runner.tscn -- --play …`) needs a `--log-file` of its own: it
  fails a test on that log's errors only, and without one says it watches none (`domain-testing`, its log gate).
- Ready when the log shows `[cmd] listening on 127.0.0.1:<port>`. Nothing after ~10 s (display/GPU init hang): kill it and
  launch again.
- The command server runs only from the editor binary, with a port (`GODOT_CMD_PORT`, else `application/debug/command_port`),
  never in an exported build. The checks run with `GODOT_CMD_PORT=off` (`domain-general`).
- The change's tests in a window for the user to watch: `tools/play_tests.sh` (`domain-testing` (`in-game-runner.md`)).

## 3. Drive with `tools/gcmd.py`

`python3 tools/gcmd.py [--port N] "<line>"`; port = `--port`, else `$GODOT_CMD_PORT`, else 9080. A line is a curated verb
(`help` lists them) or a GDScript expression evaluated on the command-server node (helpers `player()`, `scene()`,
`node(path)`; `eval EXPR`). Two verbs worth knowing: `match` (every combatant's health/act/alive, the verdict, elapsed s) and
`ai` (every NPC's brain as JSON: the state text Von saw, menus and pick, contacts, commitment timers, pathing: use it before
guessing from logs). `aim X Y` works windowed only.

Each command replies on the socket (`ok`, a value, `error: …`) and is echoed in the game log as `[cmd] <line> -> <reply>`
beside the gameplay lines it caused. `tail` the editor log or `$TMPDIR/godot_run.log`; failure markers: `SCRIPT ERROR`,
`error:`.

## 4. Clean up

`kill` the Bash-launched pid (leave a `show-me` editor open). A hard kill skips `_exit_tree`, so the Von decision server it
spawned (port 8000) is orphaned: **always `pkill -f "von serve"` after one.** An orphaned server answers HTTP but its stdout
pipe is dead, so every decision fails (`422 Failed to load Option-Marker decision weights … [Errno 32] Broken pipe`) and
every NPC sits in `HOLD`.
