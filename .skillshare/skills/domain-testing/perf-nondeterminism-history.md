# Perf · what was shown before the determinism jobs (#203)

Side file of `perf-nondeterminism.md` (the reading rule and the state of #203 live there); the dated traces it leans on.

## What was shown before #203 (2026-11-07, scratch traces, `Perf.configure_match` 5v5)

- Base 1afec1d2 alone was not deterministic (contact at 11.1, 13.0, 11.2 s; the traces first split at frame 78): the planning re-bake landed on a
  worker thread, on a wall-clock frame. With it off each revision was stable run to run but played its own match, and 40 ms a frame
  changed none of it; any change to what the process allocates moved it.
- `perception_house.gd` phased each NPC's look by `perception.get_instance_id() % LEARN_EVERY_FRAMES`; ids step in fixed strides, so
  the phases clustered and moved with allocations (merged: nine NPCs on one frame). Handed out in turn since (`look_phases.gd`; `ai/perception/
  sight_learning_staggered`, `look_phases_two_worlds`, `house_look_cadence`). The sight cadence, the give-way order and the unseeded
  global `randf` were left, and are #203's.

## The fingerprint's first reading (2026-11-10, #203, before the determinism jobs)

Each guard twice with the fingerprint, padding off and on, at load 14 to 18 with 20+ other Godot. No pair matched; the first differing
frame, run 1 against 2, was 77 / 10 (5v5), 72 / 74 (grenade), 32 / 48 (10v10) and 57 / 31 (vision), off / on: a position a pixel or
three off, a goal, or an NPC's health with no shot logged, all long before contact (6 s, frame 360, or later). Padding off against on
differed too (frames 10, 120, 32, 49). Those are the jobs' starting point, not a state of the code.
