# Ticket: ai

Follow `story.md`; load `domain-ai` (its map points to the sub-domain files the work touches). Fixing
behaviour that already exists is a bug: `bug.md`.

## Grilling: real tactics

Search the web for how it is done for real: published tactics and doctrine, training material, how people move, shoot,
communicate and react in that setting. Run it through `mattpocock-skills:research` (a background agent, primary sources, a
cited file in `docs/research/<slug>.md`) and keep grilling while it reads; the questions that hang on it wait for it. Put
what you find (and where reality differs) into the questions, the brief and the test scenarios, and link the file from the
plan. Don't shape the behaviour around what the AI, snapshot or navmesh can do today.

## Tests: the whole pipeline

- Location: `tests/ai/<topic>/<name>_test.gd` (topics are the folders under `tests/ai/`); shared setup in
  `tests/_ai/<name>_probe.gd`.
- **Scenario tests script nothing:** perception, snapshot, the real Von server at every tree level, behaviour, radio and
  guard all run. `"requires_von": true`, tag `von`: recorded once with `tools/run_tests.sh --record-von --id=<id>` (commit
  `<name>_test.von.json`), replayed in every run; `--require-von` runs it live. `live_only` (never replayed) is for a test of the transport itself and for
  `ai/investigate/defenders_stay_in_house_quiet_von`, a 40 s generated-house match whose fight moves the NPCs by a hair
  differently in a replay.
- Build the world so the decision under test is the natural one (nearest doorway, the one unsearched room, the hostile in
  view), and `require` the AI took that path before asserting what it did there, so a surprising Von pick reads as a
  set-up finding in the bundle.
- `von_script` is for one mechanism at a time (the NPC carries out a given pick; a situation offers an option the
  contrasting one doesn't). It never replaces scenario tests. A native suite is for pure logic (a geometry helper, a
  wording rule) and may add fast checks beneath a scenario test, never replace one (`domain-testing`, "Native unit suites").
- **Leave the rest of the AI on:** build the world as a match does, keep defaults. Don't switch off `ai.*` behaviours,
  hold the NPC still, change its timers or remove what would be in the way. A switch or prop only when it is the
  scenario's premise (a part-spent magazine, an unkillable defender); comment why on each and list them in the report.
- A failure caused by another AI system is a finding: fix the conflict at its cause, never by disabling that system.
- A red scenario test is tagged `gap` and its behaviour written into the `docs/` spec (as `docs/tactical-entry.md` E10–E15
  were; `domain-testing`, "Running tests"): reported as GAP, not a run failure, and a FAIL the day it passes until the tag
  is dropped.
