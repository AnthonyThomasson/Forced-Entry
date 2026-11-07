# Perf · A revision plays its own match (2026-11-07, #192 Extension 3)

`perf/grenade_match_stress` read a sim length of 21.3 to 21.5 s merged against 20.4 s at base. The sim length is `warm_until_contact` plus the window, so it is the contact time, and
the match is chaotic: it is not a slice's logic (rules 36, 37 hold) and not the test's pacing. Never judge a match guard by its sim length or by one run.

## What was shown (a scratch per-frame trace of every NPC's rounded position, goal and act until contact, `Perf.configure_match` 5v5, load 13 to 99)

- Base 1afec1d2 alone is not deterministic: contact at 11.1, 13.0, 11.2 s (frames 679, 679, 686, 700); the traces first split at frame 78. The planning re-bake
  (`NavRebake._bake_async`) lands on a worker thread, on a wall-clock frame. With `nav.rebake` off, base was identical to frame 743 with 40 ms a frame added.
- With it off, each revision is stable run to run but plays its own match: draw tip 30df4be3 and decision tip dd213e7f leave base at frame 64 (3 of 3), merged 5e011817 at 41
  (3 of 3), vision tip e6394e46 matches to 781; 40 ms a frame changes none of it, and switching `BodyDrawCache` off does not return to base. Base with only extra logging in the
  probe left its trajectory at frame 64 too, and padding the physics RIDs before the world built moved it again: any change to what the process allocates moves the match.
- Mechanism found: `perception_house.gd` phased each NPC's scheduled look by `perception.get_instance_id() % LEARN_EVERY_FRAMES`. Ids step in fixed strides, so the phases
  clustered and moved with allocations: base [4,2,4,0,2,4,0,2,4,0], draw [0,2,2,2,2,2,2,2,2,2], decision [2,0,2,4,0,2,4,0,2,4], merged [4,0,0,0,0,0,0,0,0,0] (nine NPCs on one frame).
  Now handed out in turn (`look_phases.gd`; `ai/perception/sight_learning_staggered`, `look_phases_two_worlds`, `house_look_cadence`).
- Still keyed on allocation, not changed: the sight cadence (`perception_sight.gd`, `(frame + ids) % SIGHT_EVERY_FRAMES`) and the give-way order (`loco_give_way.gd`, the lower
  instance id). Patching only the look phase in scratch copies of base and merged still split them at frame 64 with identical NPC state to there (a physics order), and global `randf`
  (projectile, casing, explosion, ragdoll) is unseeded from the first shot.

## Reading rule

Compare two revisions by interleaved runs (A, B, A, B), `uptime` before each, the contact time (`PERF <label> contact at`) recorded beside avg / p95 / max. Never conclude from one run.

## After the look-phase fix, the branch against base (2026-11-07)

Interleaved, HEAD `d2f20dea` against `1afec1d2`, ungated at load 10 to 19 with 29 to 40 other Godot: the branch's average frame was higher in 8 of 8 pairs (`grenade_match_stress`
+0.4 to +1.8 ms, `match_10v10_stress` +2.0 to +3.9 ms). Each revision plays its own match, so this is not isolated: a real cost and a different fight read the same. Recorded, not
resolved (the user chose to move on); #195 holds it. Table and caveat: `perf-district-ext3.md`.
