# Extension 3's two spikes: why 10v10 and npc_vision stay red

Side file of `perf-district-ext3.md` (`perf-district.md`, `perf.md`, `domain-testing`).

Copied from the spike reports; `/tmp` is not durable.

### `spike-ext3` (HEAD 1afec1d2, 2026-11-07; scratch worktrees, ungated, load 3.3 to 6.5; M = measured, E = estimated)

- **10v10 is dominated by the fixed per-NPC cost.** With every decision free the instrumented p95 is still 23.2 and the no-decision frames' p95 is 21.0. Stock 10v10: p95 25 to 29, max 33 to 59.
  A calm frame is about 14.7 ms: `observe` 2.8 (`sight.see` 2.2), `behavior.apply` 3.0, `anatomy.step` 2.0, other controller about 2.3. 24.5 % of the frames hold a decision (a decision frame
  averages 27 ms), 9.1 ms a decision (build 5.6 plus walk 3.1; the perf Von stub answers synchronously).
- **The decision build has no single hot spot** (per decision, 10v10: `snap.build` 5.73 ms with 420 rays, 21 routes, 58 snaps; `_per_target` 4.06; `tac.fire_positions` 2.47; `_safe_spot` 1.10;
  `retreat_group` 1.26). Rays are about 23 % of a build, routes 14 %, snaps 9 %, the other 54 % GDScript overhead. The heavy decile of decisions (17 to 19 ms) is the lazy `grenade_ready` fact
  (`tac.throw_points` 7.4 ms in the 10v10, `thr.shots_possible` 10.6 in the grenade match); it is read in about 97 % of decisions with a hostile known.
- **Identical savings are small:** the micro bundle (`_route_exposed` early exit, snap memos, `_safe_spot` ordering, cheaper `is_cover`) is about 1.0 ms a decision at 10v10 (E), 0.3 at the grenade match,
  10v10 p95 about -1.5 (E; stock still about 26.5). Rays repeat 11 % inside a decision, snaps in the walk 43 to 50 %, routes about 0 %; consecutive decisions of one NPC differ, so a cross-decision cache has little to hit.
- **Slicing a decision** (E, replayed): pieces packed to at most 4 ms take the 10v10's stock p95 from about 25.9 to 23.3 and leave max about 46; at most 3 ms, 22.4. It costs 1 to 3 frames of latency
  (small against Von's about 100 ms) and breaks tests that pin the state at the decision's start tick (a delayed walk by one frame fails `ai/decision/order_transport` and
  `ai/decision/unordered_state_unchanged`; by two also `ai/entry/entry_ajar_door_hostile_in_gap`). `DecisionBudget.per_frame` 1 means no two decisions share a frame.
- **Max stays above 33.4 in every 10v10 replay** (E 39 to 44 stock): single events set it (an escape search about 9 ms, a nav tick 7.8, engine spikes). Nav tick spreading gains about 0.
- **The grenade match's floor is the character draw:** 5.1 ms of about 12 ms average (M: drawing disabled reads avg 7.25, p95 13.9 against 12.4 and 19.8), 9.5 draws a frame at about 0.47 ms
  (`_draw` 4.46 plus shadow 1.16). A walking body's redraw key changes in about 95 % of in-view character-frames, so a "cache what is unchanged" scheme has little static part to keep (the draw caches' small gain).
  Half-rate redraw was about -2 ms (M) but is not identical and conflicts with `standing_body_repaints_on_change`. Its max outliers (24 to 51 ms) are engine or blast frames.
- **Ranked:** identical draw caches; slice decisions into 3 to 4 ms deterministic pieces (10v10 p95 -5 to -6, max little); cut the per-NPC fixed cost about 40 % (the only lever on the 10v10's no-decision p95 of 21);
  the micro bundle; LOD draw; nav tick spread. The 10v10 needs the slicing and the fixed-cost cut together and still lands near 19 to 20 stock p95 with max red.

### `spike-vision` (HEAD 1afec1d2, 2026-11-07; timed ms x 0.69 is about the real ms)

- **The player's view cost is the cone rebuild** and nothing else: on a moving viewer 13 of 14 ms of the view's frame (timed; 9.6 to 10.7 ms uninstrumented); memory, mask and composite on the CPU 0.08 + 0.05 ms,
  `ViewWatch` 0.005 ms; windowed the render side adds about 1.7 ms. About 6.4 ms of the 10.7 ms is the engine (743 rays at 5.8 us, the region shape query 6.2 us a shape, 2.1 ms for 340 shapes); the
  GDScript side identical work can touch is about 4.3 ms.
- **In a real fight the view rebuilds on 36 to 54 % of the frames** (viewed invader), 100 % while the viewer moves or turns; a "parked" viewer in the match rebuilds on 28 to 100 % (shoved by hits,
  dents, doors, which is why the guard now parks it out of reach). 67 to 83 % of the rebuilds are forced by the viewer's own eye or facing, 15 to 19 % by a world signal. Every one of the top 5 % frames (15 of 15,
  14 of 15) holds a rebuild: wall 42 to 61 ms, of which the view is 13.7 to 16.2 ms (timed).
- **Identical savings are capped** at about -2.5 ms of 10 (-25 %), most of it a high-risk shape-set cache; measured: the fan-hide table -0.9 ms (-8 to -10 %), inlining the visibility cast +0.4 (slower), a coarser sweep 0
  (the saving moves to the corner rays). A native port would be about -7 ms but is a native build in a pure GDScript project.
- **p95 20 and max 33.4 cannot be met by the view alone:** the same 10v10 with the view switched off (the relative guard's "off" blocks) reads p95 21.5 to 25.6 and max 33 to 37 (avg 10.8 to 15.1, load 4 to 7),
  so `match_npc_vision` is red on p95 and max whatever the view does. Closing them takes the decisions work and either a time-sliced rebuild (p95 / max -8 to -10 ms on rebuild frames, E, L effort) or the native port.
- **The cone flake** (`vision/cone_same_after_savings`, 2 to 8 %): `ViewCone._fan_hides` trusted two engine hit positions (about 0.02 px off a shape) to prove a corner hidden; a corner within about 3e-5 rad of a fan
  ray on a dented face of collinear vertices was falsely hidden and 3 vertices were missing. Fixed by an angular margin of `0.25 / distance` (rule 33); 514 000 comparisons with it, 0 mismatches.
- **The pose lag (rule 34)** is a spec change: every polygon drawn is the exact cone of an earlier real eye (never a quantised or invented eye, which the never-cleared memory would keep), so no phantom area is remembered.
  Its measured effect on the guards is small because the moving loop turns 6 degrees a frame and the fight forces world rebuilds; it helps a player walking with a still mouse (the eye-only phase).

### What a follow-up holds (rule 38, AC41)

Sliced decisions (deterministic work-unit pieces, tests that wait for the decision to land), a per-NPC fixed-cost cut (`sight.see`, `behavior.apply`, `anatomy.step`), and a sliced cone rebuild.
Tools used by the spikes: `/tmp/fe-perf-findings/ext3-tools/`, `/tmp/fe-vision-out/` (not in the repo).
