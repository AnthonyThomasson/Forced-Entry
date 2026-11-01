# Domain Docs

How the engineering skills consume this repo's domain documentation.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root. (A repo with several contexts has a `GLOSSARY-MAP.md` instead, pointing at one
  `GLOSSARY.md` per context, with context-scoped ADRs in `src/<context>/docs/adr/`; this one has a single context.)
- **`docs/adr/`**: the ADRs that touch the area you are about to work in.

A missing file: proceed silently, without flagging it or suggesting to create it. `mattpocock-skills:domain-modeling` creates them lazily
when terms or decisions get resolved.

These sit beside, not in place of, the `architecture` skill (the domain map and cross-domain interfaces) and the behaviour
specs in `docs/*.md` that the tests assert.

## Use the glossary's vocabulary

Name a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name) as `GLOSSARY.md` defines it, not
by a synonym it avoids. A concept the glossary lacks is either language the project does not use (reconsider) or a real gap
(note it for `mattpocock-skills:domain-modeling`).

## Flag ADR conflicts

Output that contradicts an existing ADR surfaces it explicitly rather than silently overriding:

> _Contradicts ADR-0003 (config holders split by topic), but worth reopening because…_
