---
name: change-report
description: Write the change report the user reads before approving a change - risks, alternatives, domains, tests, seams added and removed. Use right before asking the user to accept a plan or fix (`ticket-story` phase 2, `ticket-bug` before the fix, every re-acceptance), and on `/change-report`.
---

# Change report

One screen the user approves from. It sums up the plan in hand; it adds no decisions of its own. Show it as text,
then ask for acceptance (`AskUserQuestion`) in the same turn. Every revision of the plan gets a fresh report.

## Gather

1. **Domains:** each `scenes/` folder the plan adds or changes files in, named as its skill without `domain-`
   (`ai-behavior`, `ui-hud`, `objects`). An AI or UI sub-domain counts on its own.
2. **Seams:** a seam is a cross-domain call, signal, contract or shared type, i.e. an entry in `architecture` →
   "The vital interfaces" (an AI or UI sub-domain border counts). List each one the plan adds (a new interface, or a
   new member on an existing one) and each it removes. A call inside one domain is no seam.
3. **New tests:** each test the plan writes or extends, by id (`<domain>/<name>`), from the acceptance criteria.
4. **Tests possibly affected:** existing tests that touch what changes. Find them, don't guess: `tools/run_tests.sh
   --list <words>` for the behaviour, and `grep -rln` in `tests/` for every class, method, signal and tunable the plan
   changes. Group a family by prefix (`ai/entry_*`).
5. **Risks:** what could go wrong or regress (behaviour, perf on a per-frame path, test timing, a seam's callers).
6. **Alternatives:** the real choices the user could still make instead, each with its trade-off. The grilling's
   rejected options belong here.

Done when every domain in the plan's file list, every interface it names and every changed symbol's tests are
accounted for.

## Write

Exactly this shape. One line per item, at most ~15 words after the name. An empty section reads `none`.

```markdown
## Change report: <ticket number and title, or the bug in a few words>

**Domains:** ai-behavior, ai-perception, ui-hud

**Risks**
- <what could go wrong>: <how the plan guards it>

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
