# AGENTS.md — Forced-Entry

A small top-down Godot 4.4 demo, organized into sixteen isolated domains under `scenes/`.

**Always load the `architecture` skill before planning any change or exploring the codebase.**
It is the map: the sixteen domains, the cross-cutting conventions, and the whole sanctioned
cross-domain interface surface. When working *inside* a domain, also load that domain's
`domain-<name>` skill for its deep implementation detail. Behaviour specs that tests assert live in
`docs/` (`docs/flanking-behavior.md`, `docs/cover-and-stance.md`, `docs/tactical-entry.md`, `docs/gaze-and-fire.md`, `docs/grenades.md`, `docs/hearing.md`, `docs/outfits.md`, `docs/vehicles.md`, `docs/lighting.md`, `docs/leadership.md`).

**If you are working on a GitHub ticket (issue), invoke the `ticket` skill first.** It reads the
ticket's label and tells you which `ticket-<label>` skill to invoke (e.g. `spike` → `ticket-spike`).

**Checks:** on Stop, when the turn changed what lint reads, Claude runs lint and the headless load check
(`tools/stop_hook_checks.sh`). Lint is the engine's analyzer, the project lint rules and gdstyle (`gdstyle.toml`: 100
columns, tabs; format with `tools/gdstyle.sh fmt PATH`), and any finding fails it. The pre-commit hook
(`.githooks/pre-commit`) pairs each `.gd` with its `.gd.uid` and runs the tool tests, the commit's lint and the game tests
the commit can break (perf apart: `tools/run_tests.sh --domain=perf`); the commit-msg hook (`.githooks/commit-msg`) keeps
one Claude model per branch. Enable both once per clone with `tools/install_hooks.sh`; each script's header holds its
rules. The tests run through gdUnit4 (`addons/gdUnit4/`; `tools/run_tests.sh` drives it headless).

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `AnthonyThomasson/Forced-Entry`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
