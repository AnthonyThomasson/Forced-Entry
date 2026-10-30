---
name: ticket-story
description: Work a standard ticket (no `bug` or `spike` label; also `ai`, `harness`, `refactor`, `assets`, `graphics` and `audio`) in six phases - grill, plan on the ticket, build test by test, green + feedback gate, audit, report. Invoked from `ticket`.
model: claude-opus-5-5
---

# Ticket: story

Six phases (`ticket`, "Work in phases"). You run 1, 2, 6, the feedback gate and the findings question; 3 and 4 go to
workers, the audit always does. Label `ai`: also `ticket-ai`; `harness`: also `ticket-harness`; `refactor`: also
`ticket-refactor`; `assets` / `graphics` / `audio`: also `ticket-assets`.

## 1. Orient and grill

Load `architecture` and the `domain-<name>` skills the ticket touches; read the code it names. Run `ticket` → "Triage
checks". Answer from the code what the code can answer.

Grill with `mattpocock-skills:grilling` and `mattpocock-skills:domain-modeling`: each round asks the whole frontier
(every question whose prerequisites are settled), a recommended answer on each, through `AskUserQuestion` up to four
at a time; a term the grilling sharpens goes in `GLOSSARY.md`, a hard-to-reverse decision with a real trade-off in
`docs/adr/`. A question only something runnable can settle (does this state model feel right, how should it behave):
a throwaway sandbox under `mattpocock-skills:prototype`'s rules (named as a prototype, kept on a `prototype/<name>`
branch, the verdict on the ticket). Grill until nothing material is open:

- the outcome: what the user or player sees or can do afterwards, and what stays as it is;
- edge cases: wrong moment, nothing to act on, two at once, the thing absent; and each rule under every actor kind it
  names (an AI or a human leader, each side, a member with or without an order), with the rule that wins where two
  meet (`change-report`'s Rule interactions lists them);
- fit: which behaviour it replaces or sits beside, which domains and interfaces it touches;
- tuning and display: tunables, defaults, debug overlays, HUD, sound;
- out of scope, and what "done" means (the behaviour or tests that prove it).

The ticket text is a starting point. Stop when questions would only restate decisions.

## 2. Plan

A brief and a plan someone else could build from (the shape is `ticket` → "Brief and plan on the ticket"):

- **Agent Brief:** current behaviour; **desired behaviour** rule by rule, with the grilling's decisions; key
  interfaces (only those in `architecture`) and tunables with defaults; **acceptance criteria**, one per rule, each
  naming the test scenario and the seam it runs at (the world or `house()` it builds, the switches on): the seams
  `tdd` tests at, confirmed by the plan's acceptance; out of scope.
- **Plan:** per domain, files and types added or changed, data; test files; slices (the acceptance criteria in build
  order, each a test and the code that turns it green); open risks.

`ticket-assets`: the plan follows the showroom picks. Show it with a `change-report` and ask for acceptance; each
revision gets a fresh report. Revise until accepted. Then `ticket` → "Rebase after
acceptance", "Brief and plan on the ticket", "Show the user".

## 3. Build, test by test

The `coding` worker runs `mattpocock-skills:implement` (`ticket` → "Code goes through `implement`"), which drives
`mattpocock-skills:tdd`: one acceptance criterion at a time, in the plan's order, at the seam the plan names for it.

1. **Red.** That criterion's test (`domain-testing`, `test-debug`): behaviour through published interfaces, expected
   values from the brief, never recomputed the way the code computes them. Extend an existing test rather than add a
   near-duplicate (`tools/run_tests.sh --list <words>`). A behaviour is proved by a simulation test (a `GameTest`,
   `tests/<domain>/<name>_test.gd`); a native gdUnit suite (`tests/<domain>/<name>_suite.gd`, `extends UnitSuite`) is
   for pure logic only and may add fast checks of a pure function beneath it, always supplementing the simulation
   test, never replacing it (`domain-testing`, "Native unit suites"). Run it alone, Bash sandbox disabled
   (`tools/run_tests.sh --id=<domain>/<name>`); it must **fail for the right reason** (the behaviour is missing, not a
   parse error, race or setup mistake). Passes at once: too loose or already built; tighten it, or report it built.
2. **Green.** The smallest production change that passes it, in the right domain, through published interfaces only.
   Never loosen, skip or special-case a test. Load check and lint (`godot-run`), then the test again.
3. **Next criterion.** No code for a later one ahead of its test; refactoring waits for the review.

Then the whole suite, the `code-review` self-review and the commit, as `implement` ends. The worker's `worker_done`
lists each criterion's red line (why it failed) and green line; tell the user.

## 4. Green and wrap up

New tests pass (`--repeat=10` if timing-dependent), then `tools/run_tests.sh --changed --summary`, then
`tools/run_tests.sh --summary --jobs=auto`. A change under `scenes/ai/` or `scenes/testing/` runs
`tools/run_tests.sh --domain=ai --require-von` once, whatever its labels (the other runs skip the Von tests: the totals
line names them apart, and `--changed` ends with a `NOTE` when it skipped some). Touched a per-frame path:
`tools/run_tests.sh --domain=perf --quiet` (it waits for a quiet machine; judge only a result not marked `loaded`). An older test now failing is your regression until shown otherwise. Update every changed domain's skill,
`architecture` for an interface, and the `docs/` spec if there is one. Then `ticket` → "Feedback gate".

## 5. Audit

`ticket` → "Audit".

## 6. Report, then retro, then finish

`ticket` → "Report, then retro, then finish".
