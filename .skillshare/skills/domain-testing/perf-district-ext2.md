# Performance guards on the district: #192's Extension 2 runs and profile

Side file of `perf-district.md` (`perf.md`, `domain-testing`).

## After #192's Extension 2 (2026-11-07): AC34 is NOT met, the escape tail is gone

The escape search is pruned (nearest route first, stop past the best) and capped at `AgentGrenades.ESCAPE_CAP` 3 a physics frame (fresh plans first, a
replan keeps one slot; `docs/grenades.md` G16: an NPC may start its run up to 3 frames late, which matches the code). A call now costs 3.4 ms (5.7 and 6.4 before), at most 3
run in a frame, 59 and 50 calls in the grenade match's 560 frames (53 and 49 before, in 29 and 28 frames over 20 ms).

**Not `--quiet` runs, on purpose.** The quiet gate counts every Godot process, and 13 are on this machine (other sessions' editors and `godot-mcp` servers, none a
test's of this worktree), so it would wait for ever. The two runs are `tools/run_tests.sh --domain=perf --summary --verbose` with none of this worktree's Godot left
over; `uptime` 1-minute load 4.93 before and 3.24 after run 1, 3.24 before and 4.77 after run 2; the `PERF` lines read load 3.2 to 5.7 and 10 to 13 other
Godot. None is marked `loaded`, none is claimed `--quiet`.

| Guard (ms) | run 1 avg / p95 / max | run 2 avg / p95 / max | budget |
|---|---|---|---|
| `match_5v5_stress` | 7.09 / 13.69 / 22.06 | 7.59 / 15.22 / 23.81 | 16.7 / 20 / 33.4: **green** |
| `grenade_match_stress` | 11.61 / 19.05 / 29.59 (green) | 12.60 / **20.80** / 31.51 | p95 red in run 2 |
| `match_10v10_stress` | 13.58 / **21.74** / 30.13 | 13.46 / **23.22** / **50.03** | red |
| `match_npc_vision` | **20.45** / **33.06** / **48.67** | **19.11** / **32.60** / **40.16** | red |
| `match_npc_vision_relative`, parked | **5.48** (rounds 1.2 to 8.5) | 1.21 (rounds -1.6 to 6.5) | 3.2: red once, green once |
| the same, moving | 13.00 (cone ratio parked 0.27, moving 0.42) | 12.97 (0.13, 0.45) | 20: green |

The other twelve guards pass (nav re-bake 56.1 and 54.6 ms, steering 2.65 and 2.60, 300 queries 23.9 and 22.9, a district 157.5 and 158.8, 12 houses 1883 and 1859).
Against Extension 1: the grenade match's p95 fell from 24.3 and 18.5 to 19.05 and 20.8 and its max from 37.7 and 35.5 to 29.6 and 31.5; the 10v10's p95 and max
are unchanged within the run-to-run spread (p95 27.1 and 25.9 then, 21.7 and 23.2 now; max 56.1 and 37.9 then, 30.1 and 50.0 now), and it never threw a grenade (zero escape
calls). AC34 (all four match guards within budget) is not met. No budget is loosened, no test skipped or tagged.

### Profile of the frames that set p95 and max (2026-11-07, HEAD 05f0b476)

`Time.get_ticks_usec` accumulators on a throwaway checkout of HEAD (never committed, deleted): `fe-prof-patch-ext2.py` (profile-2's `patch_prof.py` in `deep` mode, output
to `/tmp/fe-ext2/out`), two runs each of `match_10v10_stress` (300 frames) and `grenade_match_stress` (560), ungated, load 3.8 to 5.6. Instrumented frames cost
more than stock (10v10 avg 17.6 and 18.0 against 13.5; p95 31.0 and 30.2; grenade avg 13.1, p95 21.4 and 20.8), so **read the shares and the deltas**.
Frame sets per run: the lower half (the 150 or 280 fastest frames), the top 5 % (15 or 28 frames: these set p95 and max), the single worst frame. Means of the two runs, ms:

| | 10v10 lower half | 10v10 top 5 % | grenade lower half | grenade top 5 % |
|---|---|---|---|---|
| frame | 13.9 | **33.0** | 10.4 | **23.8** |
| decisions (the decision start, now the job; `snap.build` inside) | 0.1 (0.1) | **11.2 (7.3)** | 0.0 (0.0) | **3.3 (1.1)** |
| per-NPC fixed: `observe` (`sight.see` inside) | 3.0 (2.3) | 3.4 (2.6) | 0.9 (0.5) | 1.0 (0.6) |
| per-NPC fixed: `behavior.apply` | 3.3 | 4.8 | 1.1 | 2.3 |
| other AI (`control` less decision, observe, apply, react) | 1.9 | 2.4 | 0.7 | 1.0 |
| `anatomy.step` (Character) | 2.0 | 2.0 | 1.2 | 1.5 |
| react / escape (`AgentThrow.escape` inside) | 0.2 (0) | 0.2 (0) | 0.4 (0) | 1.8 (1.6) |
| nav tick | 0 | 1.0 | 0 | 1.5 |
| `character_visuals` `_draw` | 0.1 | 0.2 | **3.2** | 4.0 |
| other `_draw` (blood pools, debris, shots) | 0.8 | 0.8 | 0.1 | 0.3 |
| physics engine and the rest of the physics step | 1.0 | **5.1** | 0.8 | 4.1 |
| rest (non-AI character, `_process`, render, idle, GC) | 1.6 | 2.3 | 2.3 | 3.2 |

- **10v10: the tail is the decision build.** Every frame of the top 5 % holds a decision (0.93 and 1.00 a frame; 0.03 and 0.05 in the lower half): 11.1 of the 19.1 ms the
  top frames add over the lower half, 7.2 of it `snap.build`; physics adds 4.1 (colliding pairs do not rise, 363 and 461 against 370 and 445: spikes, not contact count).
  A decision costs 5.2 and 4.7 ms on average, 18.1 and 10.8 at most. The two worst frames: 38.3 ms (decision 16.1, `snap.build` 9.5, physics 7.6) and 39.5 ms (a nav tick 12.6,
  decision 10.8). No escape call anywhere in the 10v10. The calm frame is already 13.9 ms: 20 NPCs at 0.5 ms (`observe` 3.0, `apply` 3.3, other AI 1.9, `anatomy.step` 2.0 = 10 ms),
  so a frame with no decision sits near 14 and a frame with one lands at 25 to 35.
- **Grenade match: a high floor more than a tail.** The lower half is 10.4 ms and 3.2 of it is `character_visuals` `_draw` (5761 and 5630 draws in 560 frames, about 10 a frame, the
  match framed whole by the test camera as a player's screen would show it): it is in every frame, so it moves p95 and max alike. The top 5 % add 13.4 ms over the lower half: decisions 3.3
  (a decision in 0.5 to 0.6 of those frames), physics 3.3, escape 1.4 (the cap held: at most 3 calls of 3.4 ms a frame), nav tick 1.5, `apply` 1.2. Its worst frames are
  30.3 ms (physics 13.8, decision 6.9) and 30.8 ms (a nav tick 7.7, `apply` 5.3).
- The nav tick (a steering tick, then a planning gather, one tick in about 45 frames) is in 5 to 9 of the 15 to 28 top frames of a run and is the single worst frame of 10v10 run 2 (12.6 ms).

**The three levers** (estimates by re-playing the measured frames of both runs, deltas of p95 / max on instrumented frames; not implemented):

| # | Lever | Domain | 10v10 p95 / max | grenade p95 / max |
|---|---|---|---|---|
| 1 | Make a decision build cheaper or sliced: build option groups on demand (profile-2: a build skips 2.1 to 3.2 ms; 81 % of decisions read only the `grenade_ready` existence check), or hold a build to about 6 ms a frame | AI (`agent_snapshot`, `decision`) | on demand -2.5 / -2.5; capped at 6 ms -4.4 / -4.8 | on demand -0.7 / -1.6; capped -0.6 / -0.4 |
| 2 | Redraw a character's visuals only when they change (`character_visuals` `_draw`: 3.2 ms in the lower half of the grenade match, 0.1 in the headless 10v10) | Character (visuals) | about 0 (barely drawn there) | -2.4 / -1.9 (at -60 %) |
| 3 | Cut the per-NPC fixed cost, 10 ms of the 10v10's calm frame: `sight.see` 2.3 (-40 %), `anatomy.step` 2.0 (-50 %), `apply` 3.3 | AI (perception, behaviour); Character (`anatomy`) | -1.1 / -1.0 (sight), -1.0 / -0.9 (anatomy) | -0.2 / -0.2 (sight), -0.7 / -0.8 (anatomy) |

A fourth, in Navigation: spread the nav tick over about 8 frames (-0.7 / -2.0 in the 10v10, -0.5 / -0.9 in the grenade match; profile-2 read -2.1 and -2.6 on p95 for the
quiet guards). The engine's physics step adds 4 to 5 ms to the top frames of both guards, with no lever of ours (colliding pairs do not rise). Taken together, levers 1 and 3 could bring the
10v10's p95 from about 22.5 stock to 17 to 19, and lever 2 alone the grenade match's p95 from 19 to 21 down to 17 to 18; the 10v10's max (30 to 50) and the viewed-NPC guard still need
the structural change profile-2 named. Tools: `/tmp/fe-perf-findings/fe-prof-patch-ext2.py` and `fe-prof-analyze-ext2.py` (not in the repo).
