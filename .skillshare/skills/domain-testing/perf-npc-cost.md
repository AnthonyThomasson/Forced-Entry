# Perf · What one NPC costs a frame in a calm 10v10, measured (#195, job npc-cost)

Side file of `perf.md` (`perf-district-ext3-spikes.md` holds the estimates this replaces). M = measured: HEAD 1917ba46, 2026-11-12,
`perf/match_10v10_stress` with throwaway `Time.get_ticks_usec` accumulators (never committed) over its 300-frame window, `--quiet`,
load 3.2 to 4.7, no other busy Godot; 20 characters, 19 of them with a controller, avg frame 12.7 to 14.4 ms.

## Where a frame goes (ms a frame, all NPCs together; the timers cost about 1 ms of the sum)

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

- **The door scan was not a cost.** `leaves.work` is 0.07 ms a frame in all (5.9 us a call, 11.7 walking calls), `door.get_group` 1.2 us. The investigator's 0.5 to 1.5 ms was an estimate.
- GDScript's unit costs (M, 200k loops): a method call 119 ns, `Object.get` 35 ns (a `StringName` is no faster), a property 21 to 52 ns, `is_instance_valid` 27 ns, `Dictionary.duplicate`
  (17 keys) 1.5 us, `get_ticks_usec` 17 ns. What costs is allocation and the engine's queries; #192 took the easy ones (the near-solid gate, the shared character list, the reused sight query).
- Prototyped and measured, then dropped as no gain over run noise (a coarse timer on each function, two runs): skipping `PoseArms._eased` when the stance is settled (`pose.update` 0.66 to
  0.65 / 0.67), the sight loop with `_due_for_sight` and `in_view` inlined (`sight.see` 1.37 to 1.33 / 1.37), `StringName` for `is_dead` in `known()` (0.97 to 0.97 / 0.98). Their total is under 0.1 ms.
- The rest cannot be identical: `known()`'s per-sighting dict is read across frames by decision pieces; the leg and hand sweeps and `visible_points` depend on a world that moves every frame; a
  once-a-frame snapshot of the others' positions would read them before or after each moves (characters step one after another).
- So the identical share of the 40 % target is about 0.3 ms of 10 (3 %), invisible to `tools/perf_ab.sh` (same-fight medians move about 0.3 ms between runs).

## The non-identical cuts, as ceilings (M, an upper bound for the whole saving)

- Sight every 4 frames (`SIGHT_EVERY_FRAMES` 3): at most a quarter of the 36 rays, 0.13 ms.
- A settled pose skipping its spring update: `pose.update` and `legs.update` are 1.4 ms in all, and the NPCs of a calm 10v10 mostly walk or follow, so the settled share is small.
- Travel-point rays every 2nd frame: `travel_point` 0.115 ms (7.8 calls a frame) to about 0.06.
- Together at their ceiling about 1.6 ms of 10, less in practice: no cut of the fixed cost alone reaches 40 %. The levers that move the 10v10's p95 and max are the frames with a decision
  (sliced decisions) and the escape search on the frames a grenade is live (`rg.set_evade` 0.58 ms a frame on average, about 30 calls of 5.7 ms in the window).
