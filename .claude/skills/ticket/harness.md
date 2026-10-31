# Ticket: harness

Covers `.claude/skills/`, `AGENTS.md`, `docs/agents/`, hooks, `tools/` scripts (`gcmd.py`, `run_tests.sh`,
`play_tests.sh`, `editor.sh`, `von_probe.py`, `match.py` …), the dev command server (`scenes/general/command_server.gd`)
and the test runner (`scenes/testing/`). Follow every `story.md` phase; only what gets tested differs.

**Writing or editing a skill, `AGENTS.md` or a doc an agent reads:** load `mattpocock-skills:writing-for-agents` (a
description is an always-loaded pointer: short, one trigger per case). The rules for a skill:
- `SKILL.md` ≤ 12 KB, every other `.md` in the skill folder ≤ 8 KB; detail only some tasks need goes into a side file the
  `SKILL.md` points to, with its path relative to the skill folder in backticks.
- `description` ≤ 200 characters, starting with "Use", saying only when to invoke the skill; `name` equals the folder.
- Keep what the code cannot say (when to use it, invariants and gotchas, reasons, interfaces by number, pointers to the
  `docs/` spec and the tests); point to the code and the specs for the rest.

Line width: only GDScript has one (gdstyle's 100 columns, enforced by lint). Lines in Markdown, Python and shell run as long
as they need.

## What is tested

- **Skills, `AGENTS.md`, `docs/agents`:** the skill tests (`tools/tests/test_skills.py` and
  `tools/tests/test_skill_pointers.py`)
  check size caps, frontmatter, references, routing and duplication. They run with `tools/tool_tests.sh --changed`. What no
  test can check is the audit's read-through of each changed skill against the code: every file, command, flag and name
  the text mentions exists as spelled now, the text is true and every line is needed. A tool change that only rewords help text or a log
  line needs no new test: build it in `story.md` phase 3 without the red step.
- **Tools an agent uses on the app: tests first** (red first, per `story.md` phase 3): a command-server verb, a `tools/`
  script that drives, queries or inspects the game, a runner flag or report field, a probe or overlay an agent reads. Test it
  the way an agent uses it: a game test for an in-game surface (`domain-testing`; harness ones in `tests/_harness/`, run by
  `--self-test` through `tests/_harness/harness_suite.gd`), or for a script a run against the headless game or a fixture,
  checking output and exit code. A behaviour is proved by a simulation test; a native suite supplements it.
- **The runner itself** (`tools/run_tests.sh`, `scenes/testing/`) drives gdUnit4's command-line tool, so its tests are
  `tools/test_log_gate.py` (verdicts, lines, report, flags, the log gate; a fake Godot and the real engine),
  `tools/test_gdunit_wrap.py` (every catalog test one wrapper case, by id), `tools/test_gdunit_panel.py` (a run as the
  editor's GdUnit panel starts it), `--self-test` (`domain-testing`) and `tools/tests/test_run_tests_flags.py` (each flag
  the batch reads is one the wrapper forwards).
- **Picking tool tests:** `tools/tool_tests.sh --staged` runs the ones a commit can break, `--changed[=<ref>]` the ones a
  branch can. `tools/tool_tests_pick.py --why PATH...` says why a module is picked; `--sweep [--json] [PREFIX...]` gives
  every tracked file's picks in one process. In-flight checks and the coordinator's reruns use `--changed`; the whole
  discovery runs once, in a `wrap-up` worker.
- **A tool test writes only in a temp dir or a copy of the checkout** (`copy_checkout()` in `tools/test_log_gate.py`, or a
  throwaway git repo), never in the live tree; `tools/tests/test_tool_tests_stay_out.py` fails on a write to a path built
  from `ROOT`.
- Both in one ticket: test only the tool part. Game code added so a tool can read it is a tool change: test it and keep
  `architecture` true.

## Wrap-up for skill-only work

Phase 4 is: lint and load check if any `.gd` changed (`godot-run`), `tools/tool_tests.sh --changed`, a read-through of each
changed skill against the code, and a check that no other skill or doc now disagrees. The audit still runs; its skills step
is the main check.
