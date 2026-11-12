# AI · Snapshot, built in pieces (`agent_snapshot.gd`, `snapshot/snapshot_build.gd`)

`AgentSnapshot.build()` makes the whole snapshot in one call; the same build can run in resumable pieces, for a caller that spreads a decision over several steps or prices what each costs. `snapshot.md` holds the snapshot itself.

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

- One build is in flight per author: its START sets the author's per-decision scratch, so a build dropped for a new one is freed and never resumed. Nothing it did outside itself is undone, and nothing needs to be.
- The walked-route memo is open from START to FINISH, and with a build held across frames behaviour-time walks in between reuse it (`perception-views.md`): a caller that spreads a build over frames must not rely on a fresh route there.
- Test: `ai/decision/staged_build_matches_whole` (a stepped build equals `sense()` in facts, sections, options, wording and the walk over it; the confinement is frozen at the start).
