---
name: change-report
description: Use right before asking the user to accept a plan or fix (a story plan, a bug's fix gate, every re-acceptance), and on `/change-report`.
---

# Change report

One screen the user approves from. It sums up the plan in hand and adds no decisions of its own. Show it as text, then ask
for acceptance (`AskUserQuestion`) in the same turn. Every revision of the plan gets a fresh report.

## Gather

1. **Domains:** each `scenes/` folder the plan adds or changes files in, named as its skill without `domain-`
   (`ai`, `ui`, `objects`); an AI or UI sub-domain (a side file of its parent skill) counts on its own (`ai-behavior`,
   `ui-hud`).
2. **Seams:** a cross-domain call, signal, contract or shared type, i.e. an entry in `architecture` → "The vital
   interfaces" (an AI or UI sub-domain border counts). List each the plan adds (a new interface, or a new member on an
   existing one) and each it removes. A call inside one domain is no seam.
3. **New tests:** each test the plan writes or extends, by id (`<domain>/<name>`), from the acceptance criteria.
4. **Tests possibly affected:** existing tests that touch what changes. Find them: `tools/run_tests.sh --list <words>` for
   the behaviour, and `grep -rln` in `tests/` for every class, method, signal and tunable the plan changes. Group a family
   by prefix (`ai/entry_*`).
5. **Risks:** what could regress (behaviour, perf on a per-frame path, test timing, a seam's callers). Try every tool or
   command a plan step or acceptance criterion runs (a baseline, a measurement, `tools/match.py`, a runner flag) once at the
   size the plan runs it, or read its `--help` when a run is too long: one that cannot do it is a risk line, with the work it
   adds.
6. **Rule interactions:** the pairs of the brief's rules that can both fire in one scenario, each with the rule that wins;
   and each acceptance scenario another rule also reaches, with the winning rule and the test premise that pins it. Walk
   every rule under each actor kind it names (an AI or a human leader, each side, a member with or without an order).
7. **Cause** (only at a bug's fix gate and at a scope change during a fix): the hypothesis the fix rests on, the probe line
   that confirmed it (quoted), and 2–4 ranked alternatives with what ruled each out. While it is empty, the acceptance
   question waits.
8. **Alternatives:** the real choices the user could still make instead, each with its trade-off; the grilling's rejected
   options belong here.

Done when every domain in the plan's file list, every interface it names, every changed symbol's tests, every tool the plan
runs and every pair of rules that can meet are accounted for, plus the cause where it applies.

## Write

Exactly this shape. One line per item, at most ~15 words after the name. Every section but **Cause** reads `none` when
empty; **Cause** appears only at a bug's fix gate or a scope change during a fix.

```markdown
## Change report: <ticket number and title, or the bug in a few words>

**Domains:** ai-behavior, ai-perception, ui-hud

**Cause** (a bug's fix gate or a scope change during a fix)
- Hypothesis: <what the fix rests on>
- Confirmed by: `<the probe line, quoted>`
- Ruled out: <alternative, ranked>: <what ruled it out>

**Risks**
- <what could go wrong>: <how the plan guards it>

**Rule interactions**
- <rule> × <rule> in <scenario>: <the winner>; pinned by <test premise>

**Alternatives**
- <the other choice>: <its trade-off>

**New tests**
- `ai/<name>`: <what it proves>

**Tests possibly affected**
- `ai/entry_*`: <why they could move>

**Seams added**
- <from> → <to> (interface <n>, or new): `<member>`: <why it is needed>

**Seams removed**
- <from> → <to> (interface <n>): `<member>`: <why it goes>
```

Plain words, names in backticks, no file paths or line numbers, no restating the plan.
