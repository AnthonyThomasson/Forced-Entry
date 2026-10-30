---
name: ticket-bug
description: Work a ticket labelled `bug` in phases - grill the user to an agreed expected-vs-actual, then reproduce, fix and green it with the `fix` skill, then feedback and report. Invoked from `ticket`.
model: claude-opus-5-5
---

# Ticket: bug

Four phases through `orchestration` (`ticket`, "Work in phases"). You run phase 1 and the user questions; phases 2–4
are `fix`'s steps and run inline in this session, since the fix gate and the test-definition questions need the user
mid-phase.

## 1. Grill

Load `architecture` and the `domain-<name>` skill where the bug seems to live; read what the ticket points at. Run
`ticket` → "Triage checks" (already fixed? reported before?). Answer from the code what it can answer. Grill with
`mattpocock-skills:grilling` (the whole frontier per round, a recommended answer on each, through `AskUserQuestion`)
until the bug is *expected vs. actual* with nothing guessed:

- what should happen and what happens instead (exact symptom, any error text);
- the trigger: map, seed, who is in it, what they carry, the moment;
- how often (always, sometimes, one layout), since when or after which change;
- what they tried or ruled out, anything related;
- what "fixed" looks like to them.

Restate it in one or two lines and get agreement. It works as intended: `ticket` → "Closing without building". Then
`ticket` → "Rebase after acceptance" (a change in the bug's area, already fixed or moved, reopens the questions), then
"Brief and plan on the ticket" with the brief only: **Category** bug, **Current behavior** the actual, **Desired
behavior** the expected, the trigger, **Acceptance criteria** the regression test and the user's "fixed" check, and
`ready-for-agent`. Then "Show the user".

## 2–4. Reproduce, fix, green

Invoke `fix` with the agreed expected-vs-actual (plus the ticket title and useful comments) and follow it: red for the
bug's reason (tell the user the red result; passes at once or not visible headless: agree the next step with the user,
don't fix blind), root-cause fix, green, skills updated. The repro sits at the seam the agreed bug names.

An `ai` label: the regression test is scripted Von (`von_script`, one mechanism) unless the bug is in what Von picks;
then it is a real-Von scenario test as `ticket-ai` describes. Green adds
`tools/run_tests.sh --include-von --require-von --domain=ai` (tests of AI live in the one `ai` domain).

**Fix gate:** once the root cause is known (`fix` step 4) and before any production change, the planned fix goes to
the user as a `change-report` whose **Cause** section holds the cause, then an acceptance question. The red test
stays uncommitted until the fix is accepted and green. A fix that widens while it is built (another domain, rule or
shared path) goes back to the gate with a fresh `change-report`.

Then:

- **Feedback:** you point the user at the `show-me` editor (Play restarted) and ask (`AskUserQuestion`) whether the bug
  is gone. Anything still seen is a new round: failing test, fix, green, ask again.
- **Report** on the ticket: the root cause, the covering test, the red → green lines. Then ask feedback, retro or finish as in
  `ticket` → "Report, then retro, then finish"; a bug has no audit, so a feedback round is the one above (failing test,
  fix, green).
