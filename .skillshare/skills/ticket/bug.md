# Ticket: bug

Grill to an agreed bug, then reproduce, fix and green it through `fix`. The fix gate and the test-definition questions need
the user mid-step, so put them to the user as they come up.

## 1. Grill

Load `architecture` and the `domain-<name>` skill where the bug seems to live; read what the ticket points at. Run "Triage
checks" (`SKILL.md`; already fixed? reported before?). Answer from the code what it can answer. Grill with
`mattpocock-skills:grilling` (the whole frontier per round, a recommended answer on each, through `AskUserQuestion`) until
the bug is *expected vs. actual* with nothing guessed:

- what should happen and what happens instead (exact symptom, any error text);
- the trigger: map, seed, who is in it, what they carry, the moment;
- how often (always, sometimes, one layout), since when or after which change;
- what they tried or ruled out, anything related;
- what "fixed" looks like to them.

Restate it in one or two lines and get agreement. It works as intended: "Closing without building" (`SKILL.md`). Then
"Rebase after acceptance" (a change in the bug's area, already fixed or moved, reopens the questions), then "Brief and plan
on the ticket" with the brief only: **Category** bug, **Current behavior** the actual, **Desired behavior** the expected,
the trigger, **Acceptance criteria** the regression test and the user's "fixed" check, and `ready-for-agent`. Then "Show the
user".

## 2–4. Reproduce, fix, green

Run `fix` with the agreed expected-vs-actual (plus the ticket title and useful comments) and follow it: red for the bug's
reason (report the red run: the exact command and its failing output; passes at once or not visible headless: agree the
next step with the user, don't fix blind), root-cause fix, green, skills updated. The repro sits at the seam the agreed bug
names.

An `ai` label: the regression test is scripted Von (`von_script`, one mechanism), the bug's exception to `ai.md`'s
"`von_script` never replaces scenario tests"; a bug in what Von picks gets a real-Von scenario test per `ai.md`.

A fix under `scenes/ai/` or `scenes/testing/` needs no separate Von run at green: Von tests replay in the whole-suite run,
and a stale recording is refreshed with `--record-von` (`domain-testing` (`runner-flags.md`)), as `story.md` section 4 says. A fix to
the decision tree, to what Von scores or to `NpcDecisionTuning` is worth a live `--require-von --domain=ai` (replays cannot see it).

**Fix gate:** once the root cause is known (`fix` step 4) and before any production change, the planned fix goes to the
user as a `change-report` whose **Cause** section holds the cause, then an acceptance question. A fix that widens while it
is built (another domain, rule or shared path) goes back to the gate with a fresh `change-report`.

Then:

- **Feedback:** point the user at the `show-me` editor (Play restarted) and ask (`AskUserQuestion`) whether the bug is gone.
  Anything still seen is a new round: failing test, fix, green, ask again.
- **Review:** the reviewer checks that the test reproduces the bug (the reproduction commit and the reported red run), that
  the fix is the smallest right one at the root cause, and that nothing else in the area breaks.
- **Report** on the ticket: the root cause, the covering test, the red → green lines.
