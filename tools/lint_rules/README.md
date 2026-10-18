# Project lint rules

`tools/lint.sh` runs two passes: the engine's GDScript analyzer, then every rule in `tools/lint_rules/rules/`. A rule
is a project-specific check the engine cannot make: a domain reaching into another's internals, game code naming a
dev tool, a banned call. One failing rule fails the lint, so it gates `tools/run_tests.sh` and the Stop hook with
no extra wiring.

```sh
tools/lint.sh                          # engine pass, then every rule
tools/lint.sh --list-rules             # each rule's name and description
tools/lint.sh --rule=coverage_isolation   # only that rule (comma list allowed), no engine pass
tools/lint.sh --skip-rule=a,b          # every rule but those, after the engine pass
tools/lint.sh scenes/ai                # both passes limited to those paths
tools/lint.sh --quiet                  # nothing printed when clean
```

The runner (`tools/lint_rules/runner.py`) takes the same flags, plus `--root=DIR` and `--rules-dir=DIR` for tests.
Each rule prints a section, `== <name>: <description> ==`, with one line per finding and then `PASS` or `FAIL`.

The rules:

| Rule | Checks |
|---|---|
| `coverage_isolation` | nothing in `scenes/`, `tests/`, `addons/` or `project.godot` names the coverage tool (`tools/coverage/`) |

## Writing a rule

A rule is one file, `rules/<name>.py`, plus a fixture test in `tools/lint_rules/tests/`, and nothing else: the runner
loads every module in `rules/`, so `lint.sh`, `run_tests.sh` and the Stop hook pick it up. The module holds:

- `NAME`: the rule's name, what `--rule=` and `--skip-rule=` take; the file is named after it.
- `DESCRIPTION`: one line, shown by `--list-rules` and in the rule's section header.
- `check(root, paths)`: returns a list of `Finding(path, line, message)`. `root` is the tree; `paths` is None for the
  whole tree, else the repo-relative files or folders lint was given, to limit the check to. `path` is repo-relative
  POSIX, `line` 1-based (0 for a file or folder itself), `message` says what is wrong in the reader's terms.
- `ALLOW` (optional): the justified exceptions, below.

Use the helpers in `tools/lint_rules/walk.py` instead of walking the tree yourself: `files(root, dirs, paths)` lists
the files under `dirs` limited to `paths`, `lines_matching(root, path, regex)` gives a text file's matching lines,
`names_matching(path, globs)` the parts of a path named so. A check reads files and stays fast: `lint.sh` runs often.

**Rules report lines; they never fix them.** A rule writes nothing and changes nothing: the finding says where and
why, and the person or agent reading it fixes the code.

A rule that raises fails the lint (its section says what it raised), so a broken rule can never pass a tree.

## Exceptions

When a finding is justified, add an `ALLOW` entry to the rule, with the path (a file, or a folder covering everything
under it) and the reason:

```python
ALLOW = [{"path": "scenes/general/command_server.gd", "reason": "the dev command server prints its replies by design"}]
```

An allowed finding is still printed, with `(allowed: <reason>)`, and does not fail. An entry without a reason, or with
a blank one, is itself an error. There is no silent skip: never special-case a path inside `check` to make a finding
go away, and never edit the tree a rule reads to hide one.

## Example

A rule that flags a bare `print(` in game code (the game logs through `GameLog.say`, interface 15 of the architecture
skill). `rules/no_bare_print.py`:

```python
"""Game code logs through GameLog.say, never a bare print()."""
from tools.lint_rules.walk import Finding, files, lines_matching

NAME = "no_bare_print"
DESCRIPTION = "game code logs through GameLog.say, not print()"


def check(root, paths):
    return [Finding(path, line, "a bare print(): log with GameLog.say")
            for path in files(root, ["scenes"], paths) if path.endswith(".gd")
            for line, _text in lines_matching(root, path, r"^\s*print\(")]
```

It flags this file:

```gdscript
# scenes/ai/noisy.gd
extends Node


func _ready() -> void:
	print("hello")
```

and lint prints:

```text
== no_bare_print: game code logs through GameLog.say, not print() ==
  scenes/ai/noisy.gd:6: a bare print(): log with GameLog.say
  FAIL
```

Its fixture test drops a file like the one above into a temp tree, runs `runner.py --rule=no_bare_print`, and expects
exit 1 with that line; on a tree without it the rule passes. `tools/lint_rules/tests/test_runner.py` and
`test_coverage_isolation.py` show the pattern (`support.TempTree`, `support.run_runner`).
