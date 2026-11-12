# AI · Snapshot, built in pieces (`agent_snapshot.gd`, `snapshot/snapshot_build.gd`)

`AgentSnapshot.build()` makes the whole snapshot in one call; the same build can run in resumable pieces, for a caller that spreads a decision over several steps or prices what each costs. `snapshot.md` holds the snapshot itself; the **decision job** (`decision-job.md`) is the caller that steps it, one piece per work unit of `DecisionBudget`.

## The build

`AgentSnapshot.begin_build(rooms, goal, activity, gather, freeze := Callable())` returns a `SnapshotBuild` and runs nothing. `step()` runs the next piece, `next_piece()` says which kind it is (`SnapshotBuild.Piece`), `done()` and `result()` end it. `result()` is the dictionary `build()` returns. `build()` and `AgentPerception.sense()` just step every piece.

| Piece | Runs | Work |
|---|---|---|
| `START` | once | calls `gather` for the knowledge, and `freeze` for the entries that go into the snapshot as they stand then; sets `vocab.rooms`, the options' and throws' `know`; the context (`_context`, with `engaged_id`, and the decision's own `throw_memo`); picks the hostiles to analyse (`_analysed_ids`) |
| `HOSTILE` | one per hostile given full analysis | that hostile's geometry, option groups and sections (`_analyse_target`); the cheap `line` entry of every listed-but-unanalysed hostile ahead of it in the contacts' order, and of those after the last analysed one, rides with the piece |
| `FINISH` | once | the shared parts, facts, option groups, the `SnapshotDemand` set-up, the sections |

The work order is the one-shot build's, so the rays, routes and random draws are the same and a fight does not move. A lazy `SnapshotDemand` group, fact or section is still built when the walk first reads it, not by a piece; the one fact the decision job resolves ahead of the walk is `grenade_ready`, by its own throw piece (`decision-job.md`, `snapshot-demand.md`).

## `AgentPerception.begin_sense(goal, activity, engaged_id := 0)`

`sense()` staged: `begin_build` with the perception's `_gather_knowledge` (`learn_by_sight`, the contacts, the callouts, the carried grenades, the order ...) and `_frozen_entries` (a `confinement.copy()`). Both run at the START piece, so `snapshot["confinement"]` is the confinement of the build's start whatever the live one becomes by its end (`perception.md`, the confinement).

## Rules

- One build is in flight per author: its START sets the author's per-decision scratch (`vocab.rooms`, the options' and throws' `know`), so a build dropped for a new one is freed and never resumed. Nothing it did outside itself is undone, and nothing needs to be.
- **`SnapshotDemand.complete()` is a hazard to a held build.** Completing an older snapshot (the debug overlay, `NpcCadence.complete()`, the spectator card, a test) hands the shared modules that decision's rooms and knowledge (`_open`). Every piece after START therefore re-asserts the build's own (`_own_scratch`) before it reads them. The throws' per-decision caches (`ctx["throw_memo"]`: the throw spots, their candidate points and whether a spot exists, by key) are the build's own, held by its context, so an older snapshot completed in between never reaches them and a newer build never reads this one's.
- The walked-route memo (`hold_walks`, the doorway views' `begin_decision`) is held by whoever runs pieces together: `build()` / `sense()` for their whole run, the decision job for the pieces it runs in one `advance`. It is never open between frames, so a door turned or a re-bake between frames is never read through it, and never into the planner's walk (`perception-views.md`). A build it drops (a claim over it) is freed, never resumed.
- `AgentSnapshot.reread_claims(snapshot, callouts)` (through `AgentPerception.reread_claims`) makes again what a snapshot made of the radio callouts (the flank sides' `held_by` and the options and sections made from them, the hostile group's allies, `stack_has_stun`) when they are not those the build read; nothing when they are the same. It first hands the authors the snapshot's own decision (`SnapshotDemand.open`). The decision job calls it as its throw piece ends, the last thing before the walk, so a claim radioed during the build and the throw search is seen (`ai/decision/claim_seen_as_the_walk_begins`, `claim_seen_during_throw_piece`).
- `result()` asserts `done()`.
- Tests: `ai/decision/staged_build_matches_whole` (a stepped build equals `sense()` in facts, sections, options, wording and the walk over it, with an older snapshot completed between every piece; the confinement view is frozen at the start), `ai/decision/staged_build_unanalysed_hostiles` (four hostiles, the third engaged: the line entries between and after the analysed ones, one piece per analysed hostile).
