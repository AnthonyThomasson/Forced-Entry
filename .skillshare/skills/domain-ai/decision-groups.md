# AI · The decision job's group piece and grenade piece (`group_steps.gd`, `group_build.gd`)

Side file of `decision-job.md` (split out to keep it under the 8192-byte cap). The prices are `decision-prices.md`'s.

A level that first reads a lazy group (`snapshot-demand.md`) pays the whole build inside one `advance()`: `leads` 2.3 ms mean and 7.4 max (a stun in the stack pulls `entries` in, 1.6), a hostile's `grenade_throws` 0.7 mean and 4.8 max. Two pieces of the job build ahead of the walk what it reads anyway, a unit of work a step, and store it in the demand as the throw piece does, so the planner finds it built.

## `GroupBuild` and the authors

An option group is built in steps (`GroupBuild`, `snapshot/group_build.gd`): **units** (one `Callable` each) and one free **finish** that puts what they made into the group (the sort, the cap, the summary). `next_kind()` says `Kind.UNIT`, `FINISH` or `DONE`; `step()` runs one; `run()` runs all. The one-shot `lead_group` / `entry_group` (`SnapshotOptions`) and `grenade_group` / `shots_grenade_group` (`SnapshotThrows`) are `begin_*().run()`, so the one-shot and the stepped build are one code path and the work order (rays, routes, snaps, random draws) is the same.

| Group | Units, in the one-shot's order | Finish |
|---|---|---|
| `leads` | one per lost hostile (its route, and a moving one's heading), one per point heard (gunfire, then footsteps), the shots' origin (under fire, no hostile known), the allies' combat calls together | drop a lead checked since, sort by age, cap, `lead_pos`, summary |
| `entries` | one per doorway (`_entry_pick`: geometry, the slot claimed, the route) | sort (a suspect room first, then nearest), cap, wording |
| a hostile's `grenade_throws` / the shots' | one per grenade kind carried | summary |

## The pieces (`DecisionJob`)

- **GROUP** (`Stage.GROUP`), after the refusal step, only when the decision starts at the root (`_entry`, from the claim: a fight or an order starts deeper and never reads the leads): `SnapshotDemand.group_steps()` is a `GroupSteps` over `entries` (only while a stun can be thrown: `stun_stack`, which hands the leads the entries' rooms to leave out) then `leads`, each stored in the demand as it ends (`built`, `fact("leads")` then reads it). A group already built is skipped, also one that came to be built while its steps were in hand (a reader of everything).
- **THROW** is the throw search (`decision-job.md`).
- **GRENADE** (`Stage.GRENADE`), after THROW, only when it found a throw: `grenade_steps()` builds the throws of the hostile (or the shots' origin) the search found one at, one grenade kind a step. The other hostiles' groups stay lazy.
- The callouts are read again (`reread_claims`) as GRENADE ends, the last thing before the walk, so a claim that landed during any piece is seen. What the leads and entries built ahead read of the radio (`GroupReads`, `snapshot/group_reads.gd`: the allies' combat calls without their ages, and for the entries the ledger's slot claims) is noted as each begins; a group whose key differs now is forgotten (`SnapshotDemand.forget_stale_groups`: the entries, and the leads with them while a stun can be thrown, whose rooms they leave out), and the walk builds it whole as it reads it, so two NPCs bound for one doorway never pick one slot (`claim_seen_by_entries_during_throw_piece`). A claim that puts a stun in the stack (`stun_stack` changed) drops the leads the same way (`forget_leads()`). A forgotten group is a lump at the walk, rare: it takes a claim on a doorway or a combat call in the few frames the pieces last.
- **Wasted units, rare:** the entry is read at the claim, so a decision that starts at the root can walk from a deeper node (`combat`) when the NPC sees a hostile in between; the groups were built for nothing. The cost is the units spent, no wrong answer.

**Still built whole, when the walk reads it:** `search_rooms`, `explore`, `interactions` and `rooms`; the grenade throws of every hostile but the one the search found a throw at; the `odds` and `exposure` sections (the text, cheap); a group forgotten as above. Not in these pieces at all: the per-NPC fixed cost, the escape search and the cone (`decision-prices.md`).

Each step takes the demand's own scratch first (`open()`) and the memo token, as the throw search does, so an older snapshot completed in between never leaves it the wrong decision's. Every kind is priced (`group_cost_of`, `cost_group_unit` for a unit, `cost_group_finish` 0 for the finish; an unknown kind fails loudly). `_step_kind` holds the kind the steps last said, so noting the next cost never asks them again outside the pool.

Tests: `ai/decision/group_piece_matches_whole` (paces 1, 2 and 1000, an older snapshot completed between batches, with and without a stun, the shots' origin; `forget_leads`; a group built whole while a build is in hand is built once), `claim_seen_during_group_piece` (a claim radioed during the piece is in the walk's snapshot), `claim_seen_by_entries_during_throw_piece` (a slot claim and a combat call during the throw piece are in the walk's entries and leads), `decision_job_pieces_suite` (the stages, the claims read after the last, a decision below the root builds none, a job cancelled in the group or the grenade piece asks no more), `decision_job_suite` (every kind priced).
