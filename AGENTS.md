# AGENTS.md — Forced-Entry

A small top-down Godot 4.4 demo, organized into sixteen isolated domains under `scenes/`.

**Always load the `architecture` skill before planning any change or exploring the codebase.**
It is the map: the sixteen domains, the cross-cutting conventions, and the whole sanctioned
cross-domain interface surface. When working *inside* a domain, also load that domain's
`domain-<name>` skill for its deep implementation detail. Behaviour specs that tests assert live in
`docs/` (`docs/flanking-behavior.md`, `docs/cover-and-stance.md`, `docs/tactical-entry.md`, `docs/gaze-and-fire.md`, `docs/grenades.md`, `docs/hearing.md`, `docs/outfits.md`, `docs/vehicles.md`, `docs/lighting.md`, `docs/leadership.md`).

**If you are working on a GitHub ticket (issue), invoke the `ticket` skill first.** It reads the
ticket's label and tells you which `ticket-<label>` skill to invoke (e.g. `spike` → `ticket-spike`).

**Checks:** on Stop, Claude runs only lint + the headless load check (`tools/stop_hook_checks.sh`), when the turn
changed what lint reads: anything under `scenes/`, `tests/`, `addons/` or `sandboxes/`, `project.godot`, any other `.gd`
(`tools/` included) but the coverage tool's fixtures, gdstyle's own files (`gdstyle.toml`, `tools/gdstyle.sh`,
`tools/lint_gdstyle.py`), or the lint and load check themselves (`tools/lint.sh`, `tools/lint_rules/`,
`tools/lint_report.py`, `tools/lint_scripts.gd` / `.tscn`, `tools/load_check.sh`, `tools/scan_godot_log.py`). Lint is
the engine's analyzer, the project lint rules (`tools/lint_rules/`) and gdstyle (`gdstyle fmt --check` + `gdstyle
check`, config `gdstyle.toml`: 100 columns, tabs), and any finding fails it. Format a script with `tools/gdstyle.sh fmt
PATH`.
The tests run through gdUnit4 (`addons/gdUnit4/`; `tools/run_tests.sh` drives it headless). A git pre-commit hook
(`.githooks/pre-commit`) first refuses a commit that leaves a `.gd` under `scenes/`, `tests/`, `addons/` or `sandboxes/`
without its `.gd.uid` or the reverse (`tools/load_check.sh --import` writes them), then runs the game tests a commit can
break (`tools/run_tests.sh --changed`, which lints first), only when it touches `scenes/`, `tests/` or `project.godot`,
and without the performance tests, which are a separate `tools/run_tests.sh --domain=perf`; when it touches `tools/`, it
also runs the tool tests (`python3 -m unittest discover -s tools -t .`); when it touches no game code but a `.gd`
outside `addons/` and the coverage tool's fixtures, or one of gdstyle's own files, it runs `tools/lint.sh`. Enable it
once per clone with `tools/install_hooks.sh`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `AnthonyThomasson/Forced-Entry`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
