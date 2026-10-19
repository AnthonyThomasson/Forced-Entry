---
name: ticket-refactor
description: Extra rules for a ticket labelled `refactor` (with `ticket-story`) - coverage evidence from `tools/coverage.py` crossed with `audit_scan.py dead`, tests pinning what stays, re-measured after. Invoked from `ticket`.
---

# Ticket: refactor

Follow every `ticket-story` phase. A refactor rests on **evidence**: what runs in real matches and in the game tests
(`tools/coverage/README.md`), beside what is referenced (`tools/audit_scan.py`). Building or changing the coverage tool
itself is a `harness` ticket, not this one.

## 1. Gather the evidence (phase 1, before grilling)

Bash sandbox disabled: every `run` starts Godot, and a matches run the Von server. A run takes a while: start it in the
background and read code meanwhile. Measure on a quiet machine (`uptime` load under 4, Von not serving another
worktree). A run measures the working tree and is filed under HEAD; `meta.json` `dirty` marks uncommitted `scenes/` or
`project.godot` changes.

```sh
python3 tools/coverage.py run --seed=100           # matches: --matches=24 --jobs=2 --endless-every=4 [--windowed]
python3 tools/coverage.py run --tests --jobs=auto  # the game tests; args but --keep go to the copy's run_tests.sh
python3 tools/coverage.py report > "$TMPDIR/coverage.txt"   # the newest matches and tests runs of HEAD, combined
python3 tools/coverage.py report --domain=ai       # one domain; --run=DIR (repeatable) reads the run folders given
```

- Run both sources: `test-only` needs a matches run, `live-but-unpinned` a tests run.
- A run makes its instrumented copy and hit files in `artifacts/tmp/` and removes them however it ends (Ctrl-C and
  SIGTERM included); `--keep` keeps them and prints where. One killed with SIGKILL leaves them for the next run to
  sweep.
- A run folder of HEAD already under `artifacts/coverage/` is evidence: `report` reads it without a new run. With none,
  `report` exits 1 saying so.
- Pin `--seed` and keep it for the re-measure (step 5); only each process's first match is reproducible by seed.
- Drawing code (`_draw`, the pixel-art painters) runs headless too, so a headless run measures it; a `--windowed` run
  is only worth gathering when a zero in drawing code looks wrong.

## 2. Read the report

The header names the runs combined (source, commit, units, map hash) and its warnings. Then, per domain and file, one
row per function:

| Column | Reads |
|---|---|
| `line` | the function's first body line |
| `match hits` / `matches` | its hits over every match / the matches it ran in, of the header's N |
| `test hits` | its hits over every test; `(+N outside tests)` are hits while no test ran (the runner's start-up, each test's teardown): run, but pinning nothing |
| `tests` | how many tests ran it, up to three ids: the tests that pin it |
| `tags` | below |
| `uncovered` | its line ranges no run reached |
| `dead branches` | the lines of its branch arms that never ran, in a function that did |

| Tag | Reads | Before acting on it |
|---|---|---|
| `dead` | no hits anywhere, nothing references it | confirm by hand against dynamic dispatch (`m-audit-everything` Brief 1a's list); then a removal candidate |
| `dead branch` | a dead branch in a live function: an `if` / `elif` / `else` body, `match` arm or loop body that never ran | an impossible condition (remove it) or one the sample missed (a test that drives it): read the condition |
| `test-only` | hits in tests, none in matches | a dev or harness path, or a feature matches never reach |
| `untriggered system` | no hits anywhere, but referenced | wired and never triggered in the sample, or an orphaned mechanism (`m-audit-everything` Brief 1b): trace its trigger |
| `rare` | ran in fewer than 10% of the matches | live: pin it with a test before touching it |
| `live-but-unpinned` | hits in matches, none in tests | live: pin it with a test before touching it |
| `noise` | `scenes/testing/`, `scenes/ui/testing/`, the dev command server, the debug overlays, the settings menu | matches never drive these; their zeros say little |

Sections: **saturation** (new functions and lines per added match; a tail of zeros means more of the same matches find
nothing new, numbers still rising mean run more `--matches`), **failed under instrumentation**, **crashed after the
last flush** (a game process that exited non-zero once its hits were safe: recorded, no hit lost), **uninstrumented**,
**limits**.

**Trust checks, before reading any zero:**

- **Von starvation:** a header `**Warning:** N of M matches got fewer than F Von decisions per NPC per game minute`
  (`run` printed it as `WARNING:`) means those matches' NPCs held steady for want of decisions. Combat and AI code
  reading `untriggered system` or `rare` from such a run is no evidence: re-run with fewer `--jobs`, or when the
  machine is quiet. The run never lowers `--jobs` itself.
- **Mixed runs:** a warning that the runs are of different commits, or joined by (file, line, kind): re-measure both
  sources on one commit.
- **Failed under instrumentation:** each test listed ran less than it does in the real tree. A wall-clock budget fails
  from the counters' cost; any other failure, run that test in the real tree (`tools/run_tests.sh --id=<id>`).
- **Uninstrumented:** spans with no counter, never read as dead and no evidence either way: read them by hand.

## 3. Cross-check the static view

```sh
python3 -I tools/audit_scan.py dead   # what nothing references, by token (the report's dead vs untriggered rests on it)
python3 tools/test_coverage.py        # domains, switches and interfaces no test names
```

`audit_scan.py` is the view for what coverage cannot see: declarations and data. A name in both views (no hits, no
reference) is the strongest lead; still confirm it by hand.

## 4. The limits (in the plan and the report)

- Zero hits means "did not run in the sampled matches" (or tests), not unreachable.
- Coverage is per statement: the conditions inside one expression (`a and b`, a ternary) are not seen.
- Matches have no human player: player-only code (input, the leader's command menu, driving a vehicle by hand) reads
  as never run; scripted play through `gcmd` can cover it.
- Declarations and data (a `const`, a signal, a config field, an unselected data-table entry), shaders, scene wiring,
  gcmd `Expression` eval and runtime-built scripts are not measured.
- A result belongs to one commit.

**No `tools/coverage/` in the checkout:** the evidence is static only (`python3 -I tools/audit_scan.py dead`, plus
`signals`, `facts` and `events`, and `python3 tools/test_coverage.py`). Say so in the plan and the report, and claim
nothing about what runs.

## 5. Pin, change, re-measure (phases 3 and 4)

- **Plan:** each removal or rewrite cites its evidence: the report row (file, function, tag) or the `audit_scan` line,
  and the hand check that ruled out dynamic dispatch.
- **Pins first**, each before the change it guards, pin the behaviour that stays: through published interfaces, green
  before the change and after it (a pinning test passes at once; that is its job, the one exception to `ticket-story`
  phase 3's red step). `rare` and `live-but-unpinned` code the change touches gets its pin
  here. A test goes red first only for behaviour the ticket changes.
- **Delete code** only with those pins green and its evidence in the plan; zero hits alone never suffices.
- **Re-measure** in phase 4, after the green run: `run` with the same `--seed` and `--matches`, and `run --tests`. The
  removed rows are gone, every function that ran before still runs (an Endless run's later matches draw their own
  seeds, so a `rare` one may miss: check it), and no new uninstrumented span appears. Compare with the earlier folders
  (`report --run=<old matches> --run=<old tests>`) and put both in the report.
