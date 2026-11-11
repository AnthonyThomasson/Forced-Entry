# AGENTS.md — Forced-Entry

A small top-down Godot 4.4 demo, organized into seventeen isolated domains under `scenes/`.

**Always load the `architecture` skill before planning any change or exploring the codebase.** It is the map: the domains,
the cross-cutting conventions and the whole sanctioned cross-domain interface surface. Inside a domain, also load its
`domain-<name>` skill. Behaviour specs that tests assert live in `docs/` (`flanking-behavior.md`, `cover-and-stance.md`,
`tactical-entry.md`, `gaze-and-fire.md`, `grenades.md`, `hearing.md`, `outfits.md`, `vehicles.md`, `lighting.md`,
`leadership.md`, `doors.md`, `player-vision.md`).

**Working on a GitHub ticket (issue), in any role, load the `ticket` skill first.** Herdr's default workflows run the
ticket (roles, phases, pull request, merge); `ticket` routes it by label to what each kind needs planned, built and checked.

**Checks:** on Stop, when the turn changed what lint reads, Claude runs lint and the headless load check
(`tools/stop_hook_checks.sh`). Lint is the engine's analyzer, the project lint rules and gdstyle (`gdstyle.toml`: 100
columns, tabs; format with `tools/gdstyle.sh fmt PATH`); any finding fails it. The pre-commit hook (`.githooks/pre-commit`)
pairs each `.gd` with its `.gd.uid` and runs the tool tests, the commit's lint and the game tests the commit can break
(perf apart: `tools/run_tests.sh --domain=perf`); the commit-msg hook (`.githooks/commit-msg`) keeps one Claude model per
branch. Enable both once per clone with `tools/install_hooks.sh`; each script's header holds its rules. Skills live in
`.skillshare/skills/`; `.claude/skills/` is gitignored symlinks that `tools/sync_skills.sh` makes (`install_hooks.sh` and
the post-checkout hook, for a new worktree, run it). Tests run through
gdUnit4 (`addons/gdUnit4/`; `tools/run_tests.sh` drives it headless).

## Agent skills

- **Issue tracker:** GitHub Issues on `AnthonyThomasson/Forced-Entry`, through `gh`: `docs/agents/issue-tracker.md`.
- **Domain docs:** single-context, one `GLOSSARY.md` and `docs/adr/` at the root: `docs/agents/domain.md`.
