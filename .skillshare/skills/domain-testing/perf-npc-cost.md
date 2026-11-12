# Perf · What one NPC costs a frame in a calm 10v10, measured (#195, job npc-cost)

Side file of `perf.md` (`perf-district-ext3-spikes.md` holds the estimates this replaces). M = measured: HEAD 1917ba46, 2026-11-12,
`perf/match_10v10_stress` over its 300-frame window with throwaway `Time.get_ticks_usec` accumulators at about 90 sites. They were never
committed (the tree was reverted), so these numbers cannot be rerun as they are; rerun by timing the same functions again. Nine runs, `--quiet`:
the gate printed `waiting for a quiet machine: load 3.46 (under 6 wanted), 1 busy Godot (none wanted), 0.0 of 30 min` in five of them and the test
then ran; no run was marked `loaded`. Tails of two runs: `(load 3.30, 1 busy Godot)` and `(load 4.82, 0 busy Godot)`; the nine span load 3.2 to 4.8 and
0 to 2 busy Godot (the gate does not wait for a Godot that is under its busy threshold). 20 characters, 19 of them with a controller, avg frame 12.7 to 14.9 ms.

## Where a frame goes (ms a frame, all NPCs together; the timers' own cost, about 1 ms of the sum, is an estimate)

`Character._physics_process` 10.1: the controller's `control` 7.5 (`sense` 4.2, `act` 2.3, `think` 0.9), `anatomy.step` 1.9, the rest 0.7.

- `sense`: `sight.see` 1.4 (36 sight rays 0.5, the 361 per-pair checks and 19 sightings the rest), `contacts.known` 1.0 (30 us a call of dict
  copies, one 17-key `duplicate` per remembered character: 1.5 us), `react_to_grenades` 0.65 (0.58 is the escape plan: a spike on the
  frames a grenade is live, not a fixed cost), `follow_squad` 0.2, `process_events` 0.14, `house.take_in` 0.17.
- `act`: `set_up_walk` 0.6 (`walk_bodies` 0.43: its `visible_points` rays), `apply_follow` 0.5 to 0.7 and `apply_move` 0.36 (the 4 to 5 walkers a frame:
  100 to 160 us each, the nav agent's query, `_check` 19 us, `travel_point` 14 us), `entries.guard` 0.19, `apply_engage` 0.17.
- `anatomy.step` 1.9: `pose.update` 0.7 (arms 0.22, springs 0.19), `legs.update` 0.7 (`Rig.new` 0.4, the leg sweeps 0.26), the near-solid query 0.16,
  footsteps 0.15. `Hands._physics_process` 0.34 (17 us each) runs apart from the controller.
- Not per NPC: the nav tick 0.28 (2 ms every 7th frame), the lighting `_process` 0.11, projectiles 0.05.

## Identical savings: none that pays

- **The door scan was not a cost.** `leaves.work` is 0.07 ms a frame in all (5.9 us a call, 11.7 walking calls), `door.get_group` 1.2 us. The 0.5 to 1.5 ms the job's planning findings guessed for it was an estimate, not a measurement of this run.
- GDScript's unit costs (M, 200k loops): a method call 119 ns, `Object.get` 35 ns (a `StringName` is no faster), a property 21 to 52 ns, `is_instance_valid` 27 ns, `Dictionary.duplicate`
  (17 keys) 1.5 us, `get_ticks_usec` 17 ns. What costs is allocation and the engine's queries; #192 took the easy ones (the near-solid gate, the shared character list, the reused sight query).
- Prototyped and measured, then dropped as no gain over run noise (a coarse timer on each function, two runs): skipping `PoseArms._eased` when the stance is settled (`pose.update` 0.66 to
  0.65 / 0.67), the sight loop with `_due_for_sight` and `in_view` inlined (`sight.see` 1.37 to 1.33 / 1.37), `StringName` for `is_dead` in `known()` (0.97 to 0.97 / 0.98). Their total gain is under 0.1 ms: the three differences are 0 to 0.04 ms each, inside the spread of two runs of one build (`sight.see` 1.37 and 1.33).
- The rest cannot be identical: `known()`'s per-sighting dict is read across frames by decision pieces; the leg and hand sweeps and `visible_points` depend on a world that moves every frame; a
  once-a-frame snapshot of the others' positions would read them before or after each moves (characters step one after another).
- So the identical savings found are under 0.1 ms of 10 (under 1 %). A same-fight `tools/perf_ab.sh` median moves about 0.3 ms between runs (an observation of these nine runs, not a bar), so it could not show a saving this small. Nothing here proves that no identical cut exists, only that none of the listed candidates measured above the noise.

## The non-identical cuts, as bounds (not measured as cuts: nothing was built)

- Sight every 4 frames (`SIGHT_EVERY_FRAMES` 3): the bound is a quarter of the 36 rays' 0.5 ms, 0.13 ms (arithmetic on a measured cost).
- A settled pose skipping its spring update: the bound is the whole `pose.update` plus `legs.update`, 1.4 ms, which no cut reaches (bound, not measured); the NPCs of a calm 10v10 mostly walk or follow, so the settled share is small.
- Travel-point rays every 2nd frame: `travel_point` costs 0.115 ms (7.8 calls a frame); the bound is half of it, about 0.06.
- Together the bounds sum to about 1.6 ms of 10 (bound, not measured; the real saving is lower). By that sum no cut of the fixed cost alone reaches 40 %.
- The escape search is in the profile as `rg.set_evade`, 0.58 ms a frame on average, so 172 ms over the 300 frames. How many calls that was and how long each took
  was not counted in this run. The older comment in `tests/perf/match_10v10_stress_test.gd` (6.4 ms a call, 32 to 40 calls) is another fight (seed 7); dividing 172 ms by its 5.7 to 6.4 ms
  gives about 27 to 30 calls, which is arithmetic, not a measurement.
- Inference, not measured: the levers that move the 10v10's p95 and max are the frames with a decision (sliced decisions) and the grenade escape search on the frames a grenade is live.
