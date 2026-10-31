# `--changed`: which tests a change runs

`runner-flags.md` holds the other flags; `affected()` in `tools/run_tests.sh` is the domain table.

- **Mapping:** each changed file (`git diff HEAD` plus untracked; `--changed=<ref>`: below) maps to a domain; the run is
  those domains plus the ones that compose them (`affected()`, from the architecture dependency graph) in one process. `main.gd`, root scenes,
  `project.godot`, worldgen, art, general, audio, lighting and testing run everything; `scenes/testing/` and the Von stub
  add `--self-test`.
- **An edited test file** (`tests/<domain>/[<topic>/]<name>_test.gd`) runs only that test
  (`--id=<domain>/[<topic>/]<name>`) unless its domain is already running. An edited `…_suite.gd` runs its domain.
- **Helper folders** (`tests/_<x>/`): `_ai`, `_audio` and `_lighting` run that domain, `_vehicle` runs `vehicle`, `audio`
  and `general`, `_perf` the `perf` domain, `_harness` the self-tests; every other helper folder is unknown to the
  mapping, so a change to it runs the whole suite.
- **`--changed=<ref>`** covers the branch's whole work, committed or not: use `--changed=origin/main` after a commit, since a
  bare `--changed` sees only the uncommitted change and finds nothing. The merge-base rule and the refusals are in the
  `tools/run_tests.sh` usage.
- **A changed `docs/*.md` paragraph runs the tests it names.** The paragraph is the blank-line-bounded block of the new
  file holding a changed line (a pure deletion: the block around where it was). Its `Test:` / `Tests:` line
  (`tools/spec_tests.py`; a paragraph naming none takes the block that begins with `Tests:` and directly follows it)
  gives backticked names, each resolved to `tests/**/<name>_test.gd` (a name with a `/` is a path under `tests/`; under
  `--staged`, among the files the index holds). Those ids run `--repeat=5` (the larger of 5 and your `--repeat`) under
  `== tests named by changed spec paragraphs ==`, also when their domain already ran. Von ones get `--include-von` only
  when a Von server is live (else they are skipped and counted by the Von `NOTE`); `--skip-domain` still wins. A paragraph
  with no `Test(s):` line prints `NOTE docs/<f>.md:<line>: changed paragraph names no test`, a name with no file
  `NOTE unknown test name in docs/<f>.md:<line>: <name>`; neither fails the run.
- **`--changed --staged`** (the pre-commit hook's) maps what is staged (`git diff --cached`) and lints what the commit holds
  through `tools/lint_staged.sh`: the staged scripts as they are on disk, the whole tree when `project.godot`, a gdstyle
  file or a file of the lint itself is staged, none when no script is. A finding in a script not staged is labelled
  `not in this commit: <path>` (`tools/lint_label.py`), and that lint never records the clean-lint fingerprint.
  `test_log_gate.py`'s `StagedChangedTests` run it in a throwaway repo.
