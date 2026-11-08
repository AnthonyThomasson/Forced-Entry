---
name: m-audit-everything
description: Use only when the user runs `/m-audit-everything` to audit the whole codebase for rot.
disable-model-invocation: true
model: claude-opus-5-5
effort: xhigh
---

# Audit everything

Audits the codebase as it stands (`audit` covers one branch) as a file:line checklist, in phases of parallel headless workers.
**Propose, don't delete:** edit only items the user accepts (Phase 4), then Step 6. The scans find little; spend the effort
on Briefs 1b–5: **orphaned mechanisms** (live code feeding nothing), **doc drift**, **eroded boundaries**.
`tools/audit_scan.py` (its header documents `deps`, `dead`, `signals`, `facts`, `events`, `all`) reads files only; every hit
is a lead.

## Phases

You are the coordinator; each worker is a headless session ("A wave", below).

| Phase | Owner | Work | Gate |
| --- | --- | --- | --- |
| 0 — Scan | you | Step 0 survey, scans, uid check, `test_coverage.py`, `coverage.py report`, saved under `$AUDIT_DIR` | outputs exist |
| 1 — Code wave | 5 workers, parallel, read-only | **1a** unreferenced symbols · **1b** orphaned mechanisms + vestigial config · **2** redundancy · **3** isolation · **4** splits | every worker exited |
| 2 — Docs wave | up to 4 workers, parallel, read-only | **5a** `AGENTS.md` + `architecture` · **5b–5c** domain skills, sharded · **5d** code comments | every worker exited |
| 3 — Merge | you | merge reports into the Output checklist, ask which items to apply | the user answers |
| 4 — Fix + verify | one worker per disjoint file set, then one verifier | apply accepted items; Step 6 | verifier green |

Docs after code: Brief 5 drops the skill passages for what Phase 1 finds dead and describes its splits, so every Phase 2
worker gets the Phase 1 report paths. Nothing is edited before Phase 4.

**Phase 0** (workers share this worktree):

```bash
AUDIT_DIR="${TMPDIR:-/tmp}/m-audit-everything-$(basename "$PWD")"; mkdir -p "$AUDIT_DIR"
python3 -I tools/audit_scan.py all > "$AUDIT_DIR/scan.txt"
python3 tools/test_coverage.py      > "$AUDIT_DIR/test_coverage.txt"
# Every script Godot imports beside its .uid (the pre-commit hook's pairing, over the whole tree).
find scenes tests addons sandboxes -name '*.gd' | while IFS= read -r f; do [ -f "$f.uid" ] || echo "no uid: $f"; done \
  > "$AUDIT_DIR/uids.txt"
find scenes tests addons sandboxes -name '*.gd.uid' | while IFS= read -r u; do [ -f "${u%.uid}" ] || echo "orphan uid: $u"; done \
  >> "$AUDIT_DIR/uids.txt"
python3 tools/coverage.py report > "$AUDIT_DIR/coverage.txt"   # only when a run folder of HEAD exists (below)
# plus the Step 0 size table, saved as $AUDIT_DIR/survey.txt
```

`coverage.txt` is the runtime view (`tools/coverage/README.md`): `report` reads the newest run folders of HEAD under
`artifacts/coverage/` and exits 1 saying so when there are none. Then either tell the user there is no coverage evidence and
go on without it (write that line into `coverage.txt`, so the workers know), or run one first on a quiet machine, Bash
sandbox disabled: `python3 tools/coverage.py run` and `python3 tools/coverage.py run --tests --jobs=auto` (a while: 24
matches, then the whole suite). Its rows feed Briefs 1a and 1b.

**A wave.** Write each worker's spec to `$AUDIT_DIR/spec-<id>.md`, start every worker of the wave, each as its own background
Bash call from the worktree root, then wait for them all to exit:

```bash
# one per worker, on Kimi K3.1 Pro through the user's `claudep` alias (a zsh alias, hence the interactive zsh)
zsh -ic 'claudep --model kimi-k3.1-pro -p "$(cat <AUDIT_DIR>/spec-<id>.md)"' > <AUDIT_DIR>/worker-<id>.log 2>&1
```

Spec template (literal paths; a worker has no `$AUDIT_DIR`):

> **Target:** the whole codebase as it stands in `<worktree path>`; scan outputs in `<AUDIT_DIR>` (`scan.txt`,
> `test_coverage.txt`, `uids.txt`, `survey.txt`, `coverage.txt`) [; Phase 1 reports `<AUDIT_DIR>/report-*.md` for a docs worker].
> **Change:** produce the findings of `[Brief N — name, part ‹x›]` in `.skillshare/skills/m-audit-everything/[brief file]`; read
> that brief, the `architecture` skill first, then `[the domain-* skills for the domain(s) it covers]`.
> **Constraints:** read-only — edit, stage, commit, stash and ticket nothing; propose, never delete; confirm every scan hit by
> hand and name which dynamic-dispatch mechanism you ruled out; do not pad a clean section. **Ownership:** you own exactly one
> file, `<AUDIT_DIR>/report-[id].md`. **Observable acceptance:** that file holds the brief's checklist — one `- [ ] file:line —
> problem. Fix: …` per issue, `- [x] …` per confirmed-clean item, ending in a one-line verdict; your last line gives the issue
> count and the file's path. Nobody can answer a question mid-run: state an assumption in the report and go on.

Worker ids: `1a 1b 2 3 4 5a 5b 5c 5d`. 5b–5c split the domain skills into two halves of similar size (`domain-ai` and its
side files first; `domain-ui`, `domain-general`, `domain-main`, `domain-testing` in the second); each reads only its shard.
5d may split by `scenes/` subtree if large.

A non-zero exit, missing report or uncovered shard is a finding ("brief N did not complete: …"). Start no phase while a
worker of the last one is still running.

**Phase 3.** Merge every `report-*.md` into the Output checklist, keeping each `file:line` and fix verbatim; the same line
from two workers is one item. Rank split candidates by seam cleanliness. Ask which items to apply.

**Phase 4.** Accepted items only, grouped by file: one worker per **disjoint** file set, each spec naming its items and
files, acceptance "the item is gone and behaviour is identical". Then one verifier worker for Step 6, alone (it launches
Godot and Von). A failing item is reported, not silently retried.

## Step 0 — Ground truth (Phase 0)

Load `architecture`. Survey sizes for Brief 4:

```bash
cd "$(git rev-parse --show-toplevel)"
for d in scenes/*/; do
  printf "%-26s %3s files %6s lines\n" "$d" \
    "$(find "$d" -name '*.gd' | wc -l | tr -d ' ')" \
    "$(cat $(find "$d" -name '*.gd') 2>/dev/null | wc -l | tr -d ' ')"
done
find scenes -name '*.gd' -exec wc -l {} + | sort -rn | sed -n 2,16p   # the largest files
```

Read each `domain-<folder>` skill as you reach it; sub-domain boundaries (the parent skill's map) count like domain ones.

## Briefs

The spec points each worker at its brief:

| Worker | Brief |
| --- | --- |
| 1a, 1b | `brief-dead-code.md` (dead code, orphaned mechanisms, vestigial config) |
| 2, 3, 4 | `brief-boundaries.md` (redundancy, domain isolation, domains due a split) |
| 5a–5d | `brief-docs.md` (`AGENTS.md`, `architecture`, domain skills, code comments) |

## Step 6 — Nothing broke (Phase 4)

Nothing changed: say so and skip. Otherwise behaviour must be identical:
- `godot-run` load check (`--import` first if a `class_name` or script moved or was added) and `tools/lint.sh` (a removal
  can leave an unused variable: fix the code; silencing is a last resort, as in `audit`).
- `tools/run_tests.sh --changed`: a removed dynamically dispatched member fails at runtime, not at parse. A changed skill
  or `AGENTS.md`: `tools/tool_tests.sh --changed`.
- Touched anything in the 1a dynamic-dispatch list: drive it live (`godot-run`) and confirm it still happens. After a hard
  kill, `pkill -f "von serve"`.
- Rerun `python3 -I tools/audit_scan.py all`: fixed findings gone, no new `deps` edge.

## Output

By section (dead code, module complexity, documentation), highest value first; each item `file:line` — problem — fix; `[x]` on
sections confirmed clean; splits ranked with the files that move. Don't manufacture findings or soften real ones.

```
## Codebase cleanup

### Dead code
- [ ] `<file>:<line>` — <the signal / function>, nothing connects or calls it. Fix: delete it and its mention in `architecture`.
- [x] No unreferenced functions or unread declarations (N funcs scanned).

### Module complexity
- [ ] 1. `<domain>/` → `<domain>/<sub>/` — <n> of <m> files (~<lines> lines) are <sub>; interface unchanged. Moves: <files>. Edits: <preloads, docs>.

### Documentation
- [ ] `<skill file>:<line>` — says <claim>; the code does <fact>. Fix: state the real behaviour.

**Verdict:** <n> items to clear; <sections> clean.
```
