## Performance tests (domain `perf`, `tests/perf/`)

Their own category: regression guards for speed and runaway object counts, one folder, one browser section, one
selector. They are ordinary tests that load other domains, so they live apart from them:

| Test | Load |
|---|---|
| `perf/match_5v5_stress` | the whole-match case, built as Main builds one (`s.declared_match({ defenders: { count }, invaders: { count } })` over `s.house(Perf.MATCH_SEED, Perf.MATCH_PLAN)`, through `MatchBuilder.populate`: `Perf.configure_match`): a generated house pinned to the largest plan, `garage_home` (so a catalogue change never shrinks the house it fights in), five defenders at clear spots in random rooms and five invaders in one group beside the front door, each side with its spec loadout (the invaders' helmet, plate carrier and steel plates front and back, a stun and a frag each; the defenders' plain clothes; a random gun each), styled and ranked, one squad per side, every debug overlay off (the spec's `overlays` default), nav re-baker, blood, debris, sound and radio on, scripted Von; the sides in contact before the window opens (`Perf.await_contact`, a premise) |
| `perf/match_10v10_stress` | the same with ten a side: the largest match the game means to carry, held to the same standard. Each squad's members but its leader follow it (every member but the leader following is a premise), so the squads' cost (the trail, the follow spots, the `follow` primitive, the leash) is in the frame, and the sides are in contact as the window opens, so it measures the teams' fight; it logs when contact came (`PERF 10v10 match contact at <s> s`), the window (`PERF 10v10 match window: <n> knowing a hostile as it opened, <n> shots in it`) and the follow count (`PERF 10v10 match node growth ..., <n> following at the end`). **Red on a quiet machine** (its p95 and max), by the user's decision: an invader's decision that weighs its grenades (the throw spots and the escape from the burst, in its decision snapshot) spikes in one frame; the standard is untouched and the fix is #98 |
| `perf/npc_crowd_stress` | twelve scripted-Von NPCs sensing, deciding and shooting in one open furnished arena (everyone sees everyone: the decision snapshot's worst case) |
| `perf/automatic_fire_stress` | SMGs and rifles on the trigger plus pistols clicking into furniture: one run covers the single-shot and the automatic path |
| `perf/hit_overload_stress` | hundreds of hits on one chair and one character: deformation, debris, blood and their caps |
| `perf/crowd_deaths_stress` | a whole 5v5 (ten characters) killed in one frame: ragdolls, blood, bleed-out |
| `perf/furniture_pile_stress` | 120 rigid bodies shoved at once |
| `perf/bake_and_path_stress`, `perf/generate_houses_stress`, `perf/audio_bank_render` | one-shot work: nav re-bake and path queries, world-gen, the whole sound library rendered from a cold cache |
| `perf/grenade_match_stress` | P1 of `docs/grenades.md`: the 5v5 of `match_5v5_stress`, and once the sides are in contact a puppet on the invaders' side (a test actor, not one of the match's, carrying the three of each P1 names) throws three frags and three stuns among the fighters over about 3 s (through the controller contract); measured from the first throw to 3 s after the last burst. The match's invaders carry grenades of their own, so its premise (all six went off) and its among-the-fighters check count only the puppet's: its blasts by `attacker`, its stuns by the frames its own stun bursts went off in |
| `perf/ambush_order_stress` | a crew of three AI defenders in the match guards' house (`Perf.MATCH_SEED` on `Perf.MATCH_PLAN`, `s.declared_match` with no invaders) ordered, inside the window, to ambush a doorway of its leader's room nobody has ranked the posts of yet, the leader among the recipients (`docs/leadership.md` LD15, LD29): every frame of the window holds the standard, the frames each recipient's post is laid in (`EntryPosts.ambush_spot`, one decision a frame) and the one the doorway's ranking lands in among them; the order posted and every member taking its ambush are premises |
| `perf/grenade_burst_stress` | P2: a frag and a stun going off together among twelve pieces of furniture and eight characters in an arena (blood, debris, hit particles and sound on, `nav.rebake` off); the burst frame and the 2 s after it |

Thirteen guards in all. `tools/run_tests.sh --domain=perf` (or the word `perf`) runs just them; `match_10v10_stress` is red on a
quiet machine until #98. The pre-commit hook leaves them out (`--skip-domain=perf`): their frame-time budgets fail when the
machine is busy, so run them on their own before a push that touches a per-frame path. They stay in the default run, held back
from the shards and run after every shard has ended, alone in one process, and `--changed` adds the domain whenever a scene they exercise changes
(`affected()` in `tools/run_tests.sh`) or `tests/_perf/` changes. The shared helper is `tests/_perf/perf_probe.gd` (`const Perf :=
preload(...)`; not a test), with the match guards' contact: `await_contact(t, label, characters, limit_s)` runs a guard's warm-up
on until a shot has been fired and some NPC among `characters` knows a hostile at once (at most `limit_s` s more), logs `PERF
<label> contact at <s> s` and returns whether contact came (the guard `require`s it), and `knows_hostile(c)` (an NPC knowing a
hostile now, `known_contacts_for_display()`; false for a dead or freed one). The three match guards share one match and one warm-up:
`configure_match(s, per_side)` declares it (the house `MATCH_SEED` on `MATCH_PLAN`, `s.declared_match` with `per_side` a side, scripted Von, the
callouts, vision and pursuit on), `warm_until_contact(t, label, characters)` runs `MATCH_WARMUP_S` (6 s) and then `await_contact` (at most
`MATCH_CONTACT_WITHIN`, 20 s) and `require`s it as the premise, and `MATCH_LOGS` is their `allowed_logs` (the re-bake's nav lines). `character/standing_body_repaints_on_change` keeps a count but is
a functional test of its domain. A wall-clock budget belongs here and nowhere else: the lint rule `timing_in_perf`
fails a `Time.get_ticks_usec()` under `tests/` outside `tests/perf/` and `tests/_perf/` (`Time.get_ticks_msec()`, a
real-time wait's clock, is left alone), so no budget runs in the pre-commit hook.

- **Measured:** wall-clock ms per frame (`Perf.frame_stats` -> avg / p95 / max): the main-loop iteration the frame ran
  in, from its physics frame to the next iteration's first frame signal. Headless `--fixed-fps` outruns the clock and
  steps one physics frame an iteration, so that is frame-to-frame wall time, the CPU cost (rendering is not covered);
  in the GdUnit panel's run, paced to the clock, the waits between iterations are left out, so it measures the same. Also one-shot
  ms (`Perf.time_ms`) and exact counts (`Perf.nodes()`, `Despawner.count()`, dent / blood-pool caps).
- **Rendered too:** `tools/run_tests.sh --windowed --domain=perf` (or `--id=`) measures the same tests with the render in each frame.
  The two grenade tests frame the whole fight with the test camera (the runner's, or the gdUnit suite's), as a player's screen would show it, the camera locked (P1 points
  it at the match's ten with `frame(characters)`, P2 keeps the default framing of every actor), so every body is drawn; headless (a 64 px
  viewport) they size the root viewport to the project's window first, so the camera frames the same view either way. Windowed, General's `FillBatch` batches the plain-coloured shapes (off headless, which renders nothing).
  Their headless and windowed numbers, before and after issue #56, are in `docs/grenades.md`, Performance; windowed they do not all meet
  the standard yet, which is the honest state, not a reason to loosen it.
  **Windowed keeps the same budgets** (issue #78): no windowed exemption and no looser number; what a window costs is fixed at its cause,
  each fix pinned to the old pixels or bytes. The sound library's pre-warm, which synthesized on the main thread about 10 ms a frame for
  the first seconds of every windowed run (`automatic_fire_stress` 25.4 / 38.9 / 48.5 before), renders on a worker thread
  (`domain-audio`); a body's one-polygon parts (limb segments, shoulders, fists, head, a damaged body's darkened ones through
  `Deformation.darken`, the trunk's faces) and its standing shadow's plain black shapes are meshes the body keeps
  (`domain-character-body`, `body_meshes.gd`), not a polygon command each, pinned pixel for pixel by
  `character/body_mesh_matches_polygons` (windowed); a debris chunk draws its chips in pages of 32, so a chip landing or the oldest
  dropped repaints one page, not the ~1,450 chips `hit_overload` repainted a frame (3.7 ms of script windowed; `domain-physics`,
  `physics/debris_pages_match_one_batch` windowed); and a hit's spray no longer waits for its splats' merges (0.9 ms a frame), which
  finish later in the frame (`domain-physics-blood`). Measured and dropped: batching `draw_marks`' discs across marks (19 % of the
  painted pixels change where dents cluster), one body-sized bounds for every mesh (it could change which 15 lights a part keeps), the limb
  outlines as kept meshes (exact, but no faster: three A/B runs each, `grenade_match` 14.70 / 20.74 against 15.09 / 21.75 avg / p95,
  `npc_crowd` 12.01 / 21.83 against 11.56 / 19.68). The latest windowed record, from before issue #95 (the match guards then placed their own match, and a twelfth guard,
  `match_10v10_team`, measured the 10v10 with its squads): three windowed runs of the twelve perf tests on 21 October 2026
  (`tools/run_tests.sh --windowed`, each alone: no other Godot, the worktree's editor closed), this machine's quiet baseline that day
  a 1-minute load of about 5 (ordinary apps), the load sampled every 10 s through each run (its range in the header), and one headless
  run (avg / p95 / max ms; bold misses). Windowed run W2, started at 6.19, over the < 6 bar, is discarded:

  | Test | W1 (3.6-4.3) | W3 (4.3-5.6) | W4 (3.2-4.0) | Headless (2.9-3.0) | Panel (3.9-5.1) |
  |---|---|---|---|---|---|
  | `automatic_fire` (gunfire) | 13.17 / 17.12 / 19.74 | 14.44 / 18.71 / 21.55 | 14.90 / 19.64 / **42.56** | 5.39 / 7.70 / 11.50 | 13.38 / 18.50 / 24.79 |
  | `crowd_deaths` (crowd fall) | 10.87 / 16.53 / 21.83 | 12.40 / 18.57 / 23.86 | 11.67 / 18.24 / 31.64 | 8.04 / 11.77 / 17.32 | 11.92 / 17.04 / 20.38 |
  | `furniture_pile` (moving) | 1.83 / 5.60 / 5.90 | 8.48 / 10.18 / 17.17 | 6.94 / 12.83 / 18.55 | 0.73 / 2.08 / 2.86 | 3.93 / 7.61 / 24.35 |
  | `grenade_burst` (P2) | 8.94 / 11.80 / 27.85 | 9.39 / 12.64 / **34.84** | 10.29 / 12.52 / **36.40** | 6.45 / 8.28 / 22.77 | 10.49 / 13.08 / **40.50** |
  | `grenade_match` (P1) | 15.98 / **20.94** / **37.51** | 15.20 / **21.89** / 31.93 | 14.01 / **20.24** / 28.47 | 9.71 / 14.63 / 20.34 | 15.59 / **21.98** / 31.88 |
  | `hit_overload` | 11.93 / 13.96 / 15.15 | 11.67 / 13.42 / 14.64 | 12.77 / 14.81 / 16.32 | 7.86 / 9.60 / 10.38 | 12.03 / 14.94 / 17.74 |
  | `match_10v10` | 14.81 / **20.21** / 27.72 | 13.54 / 18.08 / 21.78 | 14.71 / 18.12 / 21.75 | 10.70 / 13.72 / 21.67 | 16.20 / **20.87** / 25.88 |
  | `match_10v10_team` | 11.16 / 13.37 / 17.44 | 12.09 / 15.49 / 21.32 | 11.49 / 13.84 / 31.61 | 9.49 / 13.52 / **38.69** | 12.35 / 15.21 / 17.69 |
  | `match_5v5` | 8.33 / 11.44 / 14.40 | 8.17 / 10.55 / 14.74 | 7.22 / 11.78 / 19.90 | 6.08 / 10.23 / 14.71 | 8.89 / 13.22 / 19.02 |
  | `npc_crowd` | 10.43 / 18.88 / 27.83 | 10.85 / 17.84 / 24.20 | 10.58 / 18.75 / 24.49 | 4.56 / 11.45 / 16.28 | 11.52 / 18.37 / 31.41 |
  | `bake_and_path`, `generate_houses` | pass | pass | pass | pass | pass |
  | **passed** | 10 of 12 | 10 of 12 | 9 of 12 | 11 of 12 | 9 of 12 |

  The panel column is one **Run overall** from the editor's GdUnit panel (all 588 cases, every suite, an hour; started at 22:57 at a
  load of 3.3, 2.4-6.0 through the run, the perf suite from 23:56 at 3.9-5.1; no other Godot but the editor and its runner; the
  numbers are the run's `PERF` lines in the project log): 584 passed, the harness's `gap_probe` skipped as a gap, and three perf
  tests failed, each on a measure the windowed CLI runs above miss too (P1's p95, `match_10v10`'s p95 at the margin, `grenade_burst`'s
  one-frame max), while every test that passes in all three windowed runs passes. So the panel gives the windowed CLI's perf
  verdicts: not green while P1 misses.
  `hit_overload`, which missed two windowed runs of three before the debris pages (16.3-17.2 / 19.2-20.9), passes every run.
  `match_10v10` misses its p95 at the margin even at a quiet load (20.21 in W1, at 3.6-4.3) and passes the other two. Headless,
  `match_10v10_team`'s one 38.69 frame was a one-off: `--id=perf/match_10v10_team_stress --repeat=3` alone passed 3 of 3; the other
  eleven pass. **What is left:** `grenade_match` (P1), which misses its p95 in every windowed run (20.24-21.89), and beside it the
  one-frame maxima over 33.4 ms in two of the three windowed runs (W3: `grenade_burst` 34.84; W4: gunfire 42.56 and `grenade_burst`
  36.40), besides P1's own 37.51 in W1. Of P1's windowed frame (14.0-16.0 ms on average above) about 10 ms is paid headless too (9.71
  above): the characters' physics frame with the AI it drives (6.4 ms, 0.41 ms a body in both modes, measured during #78 with a
  throwaway timer on every `_process`, `_physics_process` and `_draw`), the ragdolls, and the fallen bodies, which repaint every frame until
  they settle (about 2 ms a repaint, mostly the trunk's outline built twice, body and shadow; only 3-5 % of those repaints change
  nothing). The window adds the rest: the standing bodies' drawing on the script side (5.3 ms against 3.5 headless in that same timed
  run) and the engine's render of the frame. Closing it needs work on the AI and the fallen bodies, outside #78.
  **Since issue #95** the three match guards build a real match through `MatchBuilder` (the invaders with plates and grenades, styled
  and ranked, in squads, beside the front door), and `match_10v10_team` is folded into `match_10v10`. Re-baselined headless only
  (`--domain=perf --verbose --summary --no-lint`, three valid runs a side, each started at a load under 3.5 with no other headless
  Godot, a run whose load went over 4 discarded; old 4af0b43, new 91400e6's guard code, measured before the branch was rebased onto
  #81), medians, avg / p95 / max ms, bold misses:

  | Test | before #95 | since #95 | 7d067bf (after the review fixes) |
  |---|---|---|---|
  | `match_5v5` | 5.93 / 9.10 / 12.47 | 5.55 / 11.31 / 22.89 | 5.28 / 9.22 / 23.40 |
  | `match_10v10` | 10.88 / 14.69 / 22.42 | 11.74 / **22.04** / **65.34** | 12.11 / **25.91** / **51.13** |
  | `match_10v10_team` | 8.91 / 11.94 / 14.41 | (folded into `match_10v10`) | |
  | `grenade_match` (P1) | 10.16 / 15.09 / 24.20 | 10.58 / 17.29 / 33.18 | 10.80 / 17.14 / **35.51** |
  | `npc_crowd` | 4.49 / 10.04 / 16.44 | 4.48 / 10.62 / 16.70 | 4.66 / 12.07 / 16.83 |
  | `automatic_fire` | 5.40 / 8.24 / 10.96 | 5.52 / 8.60 / 10.47 | 5.07 / 7.80 / 10.81 |
  | `hit_overload` | 7.97 / 9.87 / 10.60 | 8.54 / 10.10 / 10.66 | 7.72 / 9.28 / 10.27 |
  | `crowd_deaths` | 7.49 / 11.80 / 16.12 | 7.48 / 11.87 / 15.72 | 7.76 / 11.72 / 16.77 |
  | `furniture_pile` (moving) | 0.72 / 2.15 / 2.61 | 0.72 / 2.14 / 2.65 | 0.71 / 2.09 / 2.47 |
  | `grenade_burst` (P2) | 6.41 / 8.47 / 22.10 | 6.89 / 8.90 / 22.50 | 6.82 / 8.39 / 22.37 |
  | `bake_and_path`, `generate_houses` | pass | pass | pass |

  The averages barely move; the tails do. The 5v5 and P1 medians pass, each grazing or missing its max in one run of three; the
  10v10's window holds 10 to 16 NPCs knowing a hostile and 21 to 48 shots (the team guard's held 2 and 0), and its p95 and max miss in
  every run: one invader's decision that weighs its grenades (`AgentTactics.throw_spot` about 5 ms a search, up to four a snapshot, and
  `AgentThrow.escape` 5 to 14 ms) takes 20 to 47 ms in one frame. With the invaders' grenades taken away its max fell within 33.4. The
  guard stays red and the standard untouched, by the user's decision; the fix is #98. Not yet re-measured windowed.
  The 7d067bf column re-measures the tree after the review fixes (the give-way's look-ahead cut to the walk left and the
  follower's catch-up run, on a per-frame path, and the three match guards on one `Perf` helper): `tools/run_tests.sh --domain=perf
  --verbose`, three runs back to back on 2026-10-24 (12:35 to 12:38), each started at a load under 4 (3.60-3.96, 3.62-4.22 and
  3.15-3.32 through the runs; none discarded), medians. Within the runs' spread: the 10v10 misses its p95 and max in every run (#98),
  P1 its max in two of three (25.30, 35.51, 50.28), the 5v5 its max in one of three (38.26), as before; every other guard held its
  budget in all three.
- **The standard:** a match runs without frame loss, so every frame-based test holds `Perf.SMOOTH_AVG_MS` (16.7, one 60 fps
  frame, the Performance overlay's target), `SMOOTH_P95_MS` (20) and `SMOOTH_MAX_MS` (33.4, two frames) through
  `Perf.within_frames(t, label, stats)` (which holds a `frame_stats` result to those three itself), at the scale of the largest match (twenty characters, `match_10v10_stress`), with no looser tail.
  One-shot work
  (`Perf.time_ms`) keeps a `const` budget at the top of its test, about 4x the baseline stated in the comment above it.
  `Perf.within` prints `PERF <label> <value> (budget <limit>)`, traces it, and fails the check with the value. Counts
  (nodes, dents, pools) are asserted tightly.
- **Measuring:** run `tools/run_tests.sh --domain=perf --quiet` (add `--verbose` to read the `PERF` lines). `--quiet` waits
  for a quiet machine and marks a result `loaded` when it gave up (which processes it gates, the load it wants and the
  timeout: `runner-flags.md`). **Judge only a result not marked `loaded`**; a `loaded` red or green says nothing about the
  code. Every `PERF` line ends with `(load <x>, <n> other Godot)`, so a number read from a log carries the state of the
  machine it came from. In a whole-suite run the perf tests run after the shards, alone.
- **Re-baselining:** run `tools/run_tests.sh --domain=perf --quiet --repeat=5 --verbose` and read the `PERF` lines. The frame standard is not
  loosened to fit a slower game: make the game faster, or state in the test why one load is heavier than a match. Update the
  "before" numbers in a test's comment only when its load changes.
- **Finding what costs:** the wall time of a frame is script time, so attribute it by timing. A throwaway `Time.get_ticks_usec`
  accumulator wrapped around the suspect functions (never committed), dumped at the end of the measured window, ranks them
  in minutes; switching a feature off with `set_static`/`switch` shows what it is worth. Measure before reading: a per-frame
  cost is rarely where the code suggests.
- **Gotchas:** a lambda captures ints by value (count into an Array); `nav.rebake` is off in tests that
  shove or shoot furniture into overlaps (re-baking overlapping holes logs a nav sync error; the nav
  test covers re-baking), and the 5v5 test, which keeps it on, allows that log (`allowed_logs`); world-gen's first run in a
  process is slower (cold caches), so its budget covers the cold case; headless runs skip the sound pre-warm, so a test that
  plays sound calls `Perf.warm_sounds()` first or turns `audio.sound` off, or the first play of each variant (9 to 35 ms) lands
  in its worst frame. A speed-up must not change what the game does: where a fast path replaces a plain algorithm, a test
  pins its output to the plain one (`navigation/furniture_union_fast_path`, `physics/blood_splat_merge_fast_path`,
  `physics/convex_pieces_match_plain_scan`, `physics/shape_polygon_cache`).
