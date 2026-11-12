# AI · Snapshot, built in pieces (`agent_snapshot.gd`, `snapshot/snapshot_build.gd`)

`AgentSnapshot.build()` makes the whole snapshot in one call; the same build can run in resumable pieces, for a caller that spreads a decision over several steps or prices what each costs. `snapshot.md` holds the snapshot itself; the **decision job** (`decision.md`) is the caller that steps it, one piece per work unit of `DecisionBudget`.

## The build

`AgentSnapshot.begin_build(rooms, goal, activity, gather, freeze := Callable())` returns a `SnapshotBuild` and runs nothing. `step()` runs the next piece, `next_piece()` says which kind it is (`SnapshotBuild.Piece`), `done()` and `result()` end it. `result()` is the dictionary `build()` returns. `build()` and `AgentPerception.sense()` just step every piece.

| Piece | Runs | Work |
|---|---|---|
| `START` | once | calls `gather` for the knowledge, and `freeze` for the entries that go into the snapshot as they stand then; opens the decision's walked-route memo (`begin_decision`), sets `vocab.rooms`, the options' and throws' `know`; the context (`_context`, with `engaged_id`); picks the hostiles to analyse (`_analysed_ids`) |
| `HOSTILE` | one per hostile given full analysis | that hostile's geometry, option groups and sections (`_analyse_target`); the cheap `line` entry of every listed-but-unanalysed hostile ahead of it in the contacts' order, and of those after the last analysed one, rides with the piece |
| `FINISH` | once | the shared parts, facts, option groups, the `SnapshotDemand` set-up, the sections; closes the memo |

The work order is the one-shot build's, so the rays, routes and random draws are the same and a fight does not move. A lazy `SnapshotDemand` group, fact or section is still built when the walk first reads it, not by a piece.

## `AgentPerception.begin_sense(goal, activity, engaged_id := 0)`

`sense()` staged: `begin_build` with the perception's `_gather_knowledge` (`learn_by_sight`, the contacts, the callouts, the carried grenades, the order ...) and `_frozen_entries` (a `confinement.copy()`). Both run at the START piece, so `snapshot["confinement"]` is the confinement of the build's start whatever the live one becomes by its end (`perception.md`, the confinement).

## Rules

- One build is in flight per author: its START sets the author's per-decision scratch (`vocab.rooms`, the options' and throws' `know`), so a build dropped for a new one is freed and never resumed. Nothing it did outside itself is undone, and nothing needs to be.
- **`SnapshotDemand.complete()` is a hazard to a held build.** Completing an older snapshot (the debug overlay, `NpcCadence.complete()`, the spectator card, a test) hands the shared modules that decision's rooms and knowledge (`_open`). Every piece after START therefore re-asserts the build's own (`_own_scratch`) before it reads them. The throws' per-decision caches (`_throws.begin()`, START) are not re-asserted: anything built by a demand read in between, which is lazy, can use them.
- The walked-route memo is open from START to FINISH, so with a build held across frames the behaviour-time walks in between reuse it (`perception-views.md`) and may be stale if a door or the map changed. The decision job spreads a build over frames when its pieces are priced above the pool: it must not rely on a fresh route there, and a build it drops (a claim over it) is freed, never resumed.
- `result()` asserts `done()`.
- Tests: `ai/decision/staged_build_matches_whole` (a stepped build equals `sense()` in facts, sections, options, wording and the walk over it, with an older snapshot completed between every piece; the confinement view is frozen at the start), `ai/decision/staged_build_unanalysed_hostiles` (four hostiles, the third engaged: the line entries between and after the analysed ones, one piece per analysed hostile).
