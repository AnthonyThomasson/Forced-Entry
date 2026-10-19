# Forced-Entry

A top-down Godot game in sixteen domains under `scenes/`; these are the words its code, tests, skills and tickets
share. The domains and their interfaces are the `architecture` skill.

## Language

### Game tests

**Simulation test**:
A game test that declares a world (an arena, a hand-laid layout or a generated house), the actors and objects in it
and which behaviours are on, runs it on the sim clock and asserts what happened: a `GameTest`, `tests/**/*_test.gd`,
named by its id (`projectile/pistol_shot_wounds`). It is what proves a behaviour.
_Avoid_: GdUnit test, integration test, scenario (the real-Von tests of one AI situation)

**Wrapper suite**:
The gdUnit4 suite that runs one folder's simulation tests unchanged, one case per test id, its cases read from the
folder's files: `tests/<domain>/<domain>_suite.gd`, or `tests/ai/<topic>/<topic>_suite.gd` for an AI topic folder.
The harness's own tests have one apart, run only by `--self-test`.
_Avoid_: test suite (any gdUnit suite), runner

**Unit suite**:
A native gdUnit4 suite of pure logic (`tests/<domain>/<name>_suite.gd`, extends `UnitSuite`): gdUnit's own asserts on a
pure function, no world. It always supplements the simulation tests, never replaces them.
_Avoid_: unit test (for a simulation test), native test

**Change's tests**:
The game tests (`tests/**/*_test.gd`) a change added or modified since its merge-base with `origin/main`, committed or
not; deleted tests, test helpers and sandboxes are not among them. `tools/play_tests.sh` plays them in a window.
_Avoid_: new tests, my tests, ticket tests

### Runtime coverage

**Run source**:
What a coverage run measures: **matches** (seeded matches played with no human, the Von server live) or **tests** (the
game tests). A report combines the newest run of each source for one commit.
_Avoid_: mode (a match's Watch or Endless mode)

**Instrumented copy**:
A throwaway copy of the repo, in the repo's gitignored `artifacts/tmp/`, in which every statement of the game's
scripts counts its own hits, on the statement's own line so lines match the source. Only the copy is changed; the
real tree stays byte-identical. A run removes it however the run ends, unless kept (`--keep`, `instrument`).
_Avoid_: build, sandbox

**Statement map**:
The list of every counted statement of one instrumented copy: its file, line, kind (function entry, branch arm or
plain statement), function and inner class. Hits are read through it, so a map belongs to one build.

**Hit file**:
The hit counts a run produced, kept apart by unit: one per match, or one per test plus one for the hits made while no
test ran. The hit files of parallel processes merge into one with the same totals.

**Uninstrumented span**:
Code the scanner was not sure how to count and left without counters. The report lists it in its own section and never
reads it as dead.

**Uninstrumented run**:
Matches played with the probe but no counters: the baseline for the counters' cost and for whether they change what a
match does. A report never reads it.

**Failed under instrumentation**:
A game test that failed or timed out in the instrumented copy. Its hits still count; a wall-clock budget can fail from
the counters' cost alone, any other failure is worth checking in the real tree.

**Von starvation**:
A match whose NPCs got fewer Von decisions per game minute than a floor (half the rate of quiet single-process
matches), because the decision server was busy. Its NPCs hold steady, so AI and combat code reads as less run than it
is; the run and the report warn.

### Report tags

Zero hits means "did not run in the sampled matches or tests", never unreachable: every tag is a lead to confirm.

**Dead**:
No hits in any run, and nothing references it.
_Avoid_: unused, unreachable

**Dead branch**:
A dead branch in a live function: an arm of an `if`, `match` or loop that never ran, inside a function that did.

**Test-only**:
Hits in the tests, none in the matches.

**Untriggered system**:
No hits in any run, but referenced: wired up and never triggered in the sample.

**Rare**:
Ran in fewer than 10% of the matches.

**Live-but-unpinned**:
Hits in the matches, none in the tests: live code no test holds in place.

**Noise**:
Code that is not play: the test harness, the dev command server, the debug overlays, the settings menu. Tagged, never
hidden; matches never drive it, so its zeros say little.

### Lint

**Lint rule**:
A project-specific check over the tree that the engine's analyzer cannot make, one module per rule. It reports lines
and never fixes them, one failing rule fails the lint, and a justified exception is a visible allow entry with a
reason.
