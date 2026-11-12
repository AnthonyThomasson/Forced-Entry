---
name: audit
description: Use before a push or PR, when asked to review the branch, and as a ticket's audit phase.
model: kimi-k3.1-pro
---

# Audit

Audits every commit since the branch left `main`, plus anything staged. Output: a checklist, each issue a `file:line` with a
concrete fix. Report only: never commit, merge, push, edit or fix unless the user asks. One agent does every step and starts
no workers. Priorities: domains **isolated**, skills **true**, comments **current**. Step 5 runs Godot, lint and tests (Bash
sandbox disabled). Two steps raising one line is one item.

## Step 0 — Scope

The change is the index against the merge-base with `origin/main` (else `main`, or `/audit <ref>`).

```bash
cd "$(git rev-parse --show-toplevel)"
BASE_REF=origin/main; git rev-parse --verify -q "$BASE_REF" >/dev/null || BASE_REF=main   # or the user's ref
BASE=$(git merge-base "$BASE_REF" HEAD)
git log --oneline "$BASE"..HEAD            # the branch's commits
git diff --staged --stat "$BASE"           # committed + staged
git diff --staged --name-only --diff-filter=d "$BASE"
git diff --staged "$BASE"                  # the hunks you are verifying; reuse for every step
git diff --stat                            # unstaged edits (not in the diff)
```

Empty diff: say so and stop. Never stage files. Unstaged edits are outside the diff but step 5 sees them: report them.

Load `architecture` (the domain table and "The cross-domain interfaces") and, once, the skill of every domain the diff touches:
`scenes/<folder>/` → `domain-<folder>`, `scenes/main.gd`, `match_builder.gd` and `match_spawner.gd` → `domain-main`. A
sub-domain's detail is a side file of its parent skill (`domain-ai`, `domain-ui`, `domain-character`, `domain-physics`: the
parent's map names it). For each interface the diff crosses, read its file, `architecture/interfaces/NN-<slug>.md` (the
index names it). A change to a parent (`goal_controller.gd`, `character.gd`, a sub-domain's role) keeps both the side file
and the parent skill true. A coupling between sub-domains that bypasses their published interfaces is an isolation finding.

## Step 1 — Domain isolation (highest priority)

For every cross-domain reference the diff adds or touches (a call into internals or a private member, a cross-boundary
`preload`, a hard-coded child path, a signal wired straight to a foreign node):

- **Published?** A call into another domain must be an `architecture` interface (a `class_name` façade like
  `Physics.spawn_debris`, a contract method like `get_surface()` / `take_hit()`, a named signal). A private method, member
  or child-node name is the smell. Fix: reroute through the interface, or promote a genuinely needed new one to a small
  façade / contract method **and add it to `architecture`**.
- **Leanest?** Reaching in by node name (`get_node("GoalController")`) couples to layout; a duck-typed lookup survives
  refactors. Prefer what knows least about the other side.
- **Direction?** `architecture`'s dependency graph has no cycles and its leaves depend on nothing outward. An edge the wrong
  way is a defect even if it works.

Each violation: `file:line`, the two domains, the reroute. Clean: say so explicitly.

## Step 2 — Should a new domain be extracted?

Signals: one feature couples to three or more domains instead of living behind one new seam; a domain grows a second,
unrelated responsibility (its header would need "and also …"); the same cross-domain glue repeats. Then recommend what
`scenes/<name>/` owns, which logic moves and the one interface the rest talks to. Nothing warrants it: one line.

## Step 3 — Skills stay true

Same current-state bar as step 4. A skill, `AGENTS.md` or `docs/agents` file in the diff gets three checks:

1. **The skill tests:** `tools/tool_tests.sh --changed="$BASE"` (step 5) runs `tools/tests/test_skills.py` and
   `tools/tests/test_skill_pointers.py` (size caps, frontmatter, references, routing, duplication). A red one is a finding.
2. **The read-through:** read each changed skill against the code, which no test can: every file, class, method, signal,
   tunable, flag and command it names exists as spelled, the text is true, and every line is needed (a line the code or a
   `docs/` spec already says, history, filler and no-ops are findings; so is anything a future change needs that was cut).
3. **Routing:** `architecture` changes in the same change when a domain is added or removed (its table, the domain count
   wherever stated, the new `domain-<folder>/SKILL.md`), a cross-domain interface changes (the interface file, the
   interface index, the dependency graph) or a cross-cutting convention changes. A `domain-<folder>` skill changes
   when its internals as described change; it names interfaces by number and leaves signatures to `architecture`.

A changed read of an entry claim (a `ClaimLedger`'s, or a `DoorStack` built from one) holds to the stale-claim rule
(`domain-ai` (`perception-stack.md`)): it names what makes a claim the current entry's, and its test has a claim left from an
earlier entry through the same doorway. Missing: `file:line` → the scope and that test.

Report drift as `<skill file>:line` → what to change.

## Step 4 — Comments (the comment rules)

The rules every audit uses (`m-audit-everything` points here). Concise, present-tense, current state only:

1. **No history or rationale-for-change.** Remove "was X", "renamed from", "moved to/from", "now emits", "no longer", "used
   to", "formerly", "previously", "(was hardcoded …)", and speculative "today / tomorrow / later / in future". Ordinary
   words describing current behaviour ("old hits", "keep the old collider") are fine.
2. **Concise.** Cut comments that restate the code or over-explain.
3. **Every method and property has a `##` doc comment** directly above, or a trailing `## …` on a one-line var/signal.
   Lifecycle overrides (the `LIFECYCLE` set of `tools/lint_rules/rules/doc_comments.py`) are exempt; a short inline `#`
   covers anything non-obvious in one.
4. **Inline `#` only for a real gotcha**: a non-obvious algorithm step, an ordering dependency, a physics/geometry
   subtlety.
5. **File header:** one `##` block at the top saying what the file is and its domain. A `class_name` holder or component
   whose name carries its domain's stem (ADR 0003, `architecture`'s holder list: `CharacterMovement`, `BloodSprayConfig`,
   `NpcEntryTuning`) names its domain by that stem, so its header need not say it again.

Rule 3, and no ticket number in a game comment (`ticket #N` / `issue #N` under `scenes/`), are lint rules (`doc_comments`,
`comment_ticket_refs`): run them, then grep the changed `.gd` files for history:

```bash
cd "$(git rev-parse --show-toplevel)"
tools/lint.sh --rule=comment_ticket_refs,doc_comments   # each finding is a file:line finding

# History / speculation (each hit should be an ordinary word)
git diff --staged --name-only --diff-filter=d "$BASE" -- '*.gd' | while IFS= read -r f; do
  grep -nHiE '\b(was |were |renamed|moved to|moved from|used to|formerly|previously|today|tomorrow| later\b|in future|hardcoded|the animator)' "$f"
done
```

## Step 5 — Load, lint, tests, behaviour

- **Load:** `tools/load_check.sh` (`godot-run`; `--import` if the change added a `class_name` or file). Report clean, or the
  exact `SCRIPT ERROR` / `Parse Error` lines.
- **Uids:** every committed script Godot imports has its `.uid` committed beside it; each path printed is a finding:
  ```bash
  git ls-files scenes tests addons sandboxes | grep '\.gd$' \
    | while IFS= read -r f; do git ls-files --error-unmatch "$f.uid" >/dev/null 2>&1 || echo "$f"; done
  ```
- **Lint:** `tools/lint.sh` (the passes and rules: `godot-run`); each finding is a `file:line` finding. **Never silence a
  warning: fix the code.** `@warning_ignore*`, an underscore prefix hiding a parameter that should go or be used, a lowered
  level in `project.godot`, a `# gdstyle:ignore` / `# gdstyle:ignore-file`, or a `gdstyle.toml` change that turns a rule
  off, lowers it or widens `exclude` / `max_line_length` is accepted only when no code change can remove it, on that one
  statement, with a comment saying why. Flag every one the diff adds (`git diff --staged "$BASE" | grep -n
  '^+.*\(warning_ignore\|gdstyle:ignore\)'`, the `gdstyle.toml` and `project.godot` hunks). After a rename that clears a
  shadowing warning, grep the function for the old name: a stale reference silently binds to the member (`name`, `visible`,
  `material`). An `ALLOW` entry the diff adds to a lint rule needs a reason that holds (`tools/lint_rules/README.md`,
  "Exceptions"). `tools/lint.sh --rule=coverage_isolation` passes: nothing in the game names a dev tool
  (`docs/adr/0001-dev-tools-stay-outside-the-game.md`).
- **Tool tests:** every new or changed `tools/` module, CLI flag, lint rule and hook block has its own test; one without is
  a finding. Run `tools/tool_tests.sh --changed="$BASE"` (sandbox disabled: some start Godot; it runs the whole discovery
  itself when the picker says `all`, and its first line says which) and each changed `tools/test_*.py` script on its own
  (`python3 tools/test_log_gate.py`: the discovery leaves them out). Report each `Ran N tests` line and every `FAIL:` /
  `ERROR:`.
- **Tests:** `tools/run_tests.sh --changed="$BASE" --summary`: the branch's commits, working tree and untracked files, and
  the tests of a doc paragraph it changed (`domain-testing` (`runner-flags-changed.md`)); a change that runs everything shards over the free Godot slots by
  itself. Von tests replay their recordings (no server); a FAIL naming `--record-von` is a stale recording to refresh, and
  `--require-von` runs them live. Report the totals line and every FAIL / TIMEOUT with its ✗ lines. Changed behaviour with no test in
  `tests/<domain>/` covering it is a finding (`domain-testing`). Each test whose checks (what it measures, a band, a
  threshold) the diff changes is compared against the ticket brief's acceptance criteria; one that checks something other
  than its criterion says is a finding.
- **Behaviour** (movement, combat, items, interactions, world-gen): also drive it live with `godot-run`. Report what you
  drove and what the game did.

## Step 5b — Spec

Does the change build what its ticket asked (the Spec axis of `mattpocock-skills:code-review`)? Find the ticket: the one the
brief names, else a `#<n>` in the branch's commits. Read its `## Agent
Brief` (`gh issue view <n> --json body`) and report, each quoting the brief line: acceptance criteria missing or only
partly met; behaviour in the diff the brief did not ask for or that its **Out of scope** rules out; criteria that look built
but wrong. No ticket, or no `## Agent Brief`: one line saying so, and skip.

## Step 6 — Show

Only when step 5 is green: invoke `show-me`. Report the worktree name, port and pid (or that it was already running).

## Output

Scope line (base ref, merge-base short sha, commit count, anything staged), then the checklist by step, each item
`file:line` — problem — fix, then a one-line verdict. Don't invent issues; clean = ready to push.

```
## Audit
Base origin/main @ 1a2b3c4, 3 commits, nothing staged.

### Domain isolation
- [ ] `scenes/main.gd:48` — couples to the NPC's child node name `"GoalController"`. Fix: find the controller by its group, `npc_controllers`.
- [x] No calls into another domain's private members.

### Skills
- [ ] `domain-physics/SKILL.md:41` — describes the 4-arg `spawn_blood`; the code takes 5. Fix: state the current signature.

### Load, lint, tests
- [x] Load clean; lint clean, no `@warning_ignore` added; `tools/run_tests.sh`: 6 passed, 0 failed, 2 skipped.

### Spec (#58)
- [ ] "Entry waypoints sit inside the room for every doorway" — only a single door is covered. Fix: add the two-door room.

**Verdict:** 2 issues to address before the branch is pushed.
```
