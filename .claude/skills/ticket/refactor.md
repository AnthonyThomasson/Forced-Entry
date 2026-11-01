# Ticket: refactor

Follow every `story.md` phase. A refactor rests on **evidence**: what runs in real matches and in the game tests
(`tools/coverage/README.md`) beside what is referenced (`tools/audit_scan.py`). Building or changing the coverage tool
itself is a `harness` ticket (`harness.md`).

## 1. Gather the evidence (phase 1, before grilling)

Bash sandbox disabled: every `run` starts Godot, and a matches run the Von server. A run takes a while: start it in the
background and read code meanwhile. Measure on a quiet machine (`uptime` load under 4, Von not serving another worktree). A
run measures the working tree and is filed under HEAD; `meta.json` `dirty` marks uncommitted `scenes/` or `project.godot`
changes.

```sh
python3 tools/coverage.py run --seed=100           # matches: --matches=24 --jobs=2 --endless-every=4 [--windowed]
python3 tools/coverage.py run --tests --jobs=auto  # the game tests; args but --keep go to the copy's run_tests.sh
python3 tools/coverage.py report > "$TMPDIR/coverage.txt"   # the newest matches and tests runs of HEAD, combined
python3 tools/coverage.py report --domain=ai       # one domain; --run=DIR (repeatable) reads the run folders given
```

- Run both sources: `test-only` needs a matches run, `live-but-unpinned` a tests run.
- A run folder of HEAD already under `artifacts/coverage/` is evidence: `report` reads it without a new run (none: exit 1).
- Pin `--seed` and keep it for the re-measure (step 5); only each process's first match is reproducible by seed.
- Drawing code (`_draw`, the painters) runs headless too; a `--windowed` run is worth it only when a zero in drawing code
  looks wrong.

## 2. Read the report

The README holds the columns, tags and sections. What to do with a tag:

| Tag | Before acting on it |
|---|---|
| `dead` (no hits, nothing references it) | confirm by hand against dynamic dispatch (`m-audit-everything`, Brief 1a's list); then a removal candidate |
| `dead branch` | an impossible condition (remove it) or one the sample missed (a test that drives it): read the condition |
| `test-only` | a dev or harness path, or a feature matches never reach |
| `untriggered system` (no hits, referenced) | wired and never triggered in the sample, or an orphaned mechanism (`m-audit-everything`, Brief 1b): trace its trigger |
| `rare`, `live-but-unpinned` | live: pin it with a test before touching it |
| `noise` | matches never drive these (testing, the command server, debug overlays, the settings menu); their zeros say little |

The **saturation** section says whether more matches would find anything: a tail of zeros means no, rising numbers mean run
more `--matches`.

**Trust checks, before reading any zero:**
- **Von starvation:** a header `**Warning:** N of M matches got fewer than F Von decisions per NPC per game minute` means
  those NPCs held steady for want of decisions; combat and AI code reading `untriggered system` or `rare` from such a run
  is no evidence. Re-run with fewer `--jobs`, or on a quieter machine (the run never lowers `--jobs` itself).
- **Mixed runs:** a warning that the runs are of different commits, or joined by (file, line, kind): re-measure both
  sources on one commit.
- **Failed under instrumentation:** each test listed ran less than it does in the real tree. A wall-clock budget fails from
  the counters' cost; any other failure, run that test in the real tree (`tools/run_tests.sh --id=<id>`).
- **Uninstrumented:** spans with no counter are no evidence either way; read them by hand.

## 3. Cross-check the static view

```sh
python3 -I tools/audit_scan.py dead   # what nothing references, by token (the report's dead vs untriggered rests on it)
python3 tools/test_coverage.py        # domains, switches and interfaces no test names
```

`audit_scan.py` sees what coverage cannot: declarations and data. A name in both views (no hits, no reference) is the
strongest lead; still confirm it by hand.

## 4. The limits (state them in the plan and the report)

- Zero hits means "did not run in the sampled matches" (or tests), not unreachable. A result belongs to one commit.
- Coverage is per statement: the conditions inside one expression (`a and b`, a ternary) are not seen.
- Matches have no human player: player-only code (input, the leader's command menu, driving by hand) reads as never run;
  scripted play through `gcmd` can cover it.
- Declarations and data (a `const`, a signal, a config field, an unselected table entry), shaders, scene wiring, gcmd
  `Expression` eval and runtime-built scripts are not measured.
- No `tools/coverage/` in the checkout: the evidence is static only (`python3 -I tools/audit_scan.py dead`, plus `signals`,
  `facts` and `events`, and `python3 tools/test_coverage.py`). Say so in the plan and the report, and claim nothing about
  what runs.

## 5. Pin, change, re-measure (phases 3 and 4)

- **Plan:** each removal or rewrite cites its evidence: the report row (file, function, tag) or the `audit_scan` line, and the
  hand check that ruled out dynamic dispatch.
- **Pins first**, each before the change it guards: pin the behaviour that stays through published interfaces, green before
  the change and after it (a pinning test passes at once; that is its job, the one exception to `story.md` phase 3's red
  step). `rare` and `live-but-unpinned` code the change touches gets its pin here. A test goes red first only for behaviour
  the ticket changes.
- **Delete code** only with those pins green and its evidence in the plan; zero hits alone never suffices.
- **Re-measure** in phase 4, after the green run: `run` with the same `--seed` and `--matches`, and `run --tests`. The
  removed rows are gone, every function that ran before still runs (an Endless run's later matches draw their own seeds, so
  a `rare` one may miss: check it), and no new uninstrumented span appears. Compare with the earlier folders (`report
  --run=<old matches> --run=<old tests>`) and put both in the report.
