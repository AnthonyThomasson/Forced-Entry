---
name: domain-ai-watch
description: Deep implementation detail for the AI WATCH module and stage (scenes/ai/behavior/watch.gd and its stage, Watch.apply) — where an NPC looks and when it takes the shot, whatever primitive it is running: the threat that holds its eyes and gun (visible, else engaged, else seen a moment ago with a clear line), the look down its path while walking, the rotating look at its room's doorways while resting, the stop on arrival, the reload reflex with a threat in view, and no sprinting with a shot to take (except a retreat). Use when editing watch.gd (Watch.apply) or Behavior's errand.aim_move / gait.should_run, or working on the NPC turning its back on a threat, staring at a wall, or seeing an enemy and not shooting; the spec and its tests are docs/gaze-and-fire.md. Complements `domain-ai-behavior`, `domain-ai-combat` and the `architecture` skill.
---

# AI · Watch (`scenes/ai/behavior/watch.gd`, and its watch stage)

Spec and tests: `docs/gaze-and-fire.md` (W1 to W6; `tools/run_tests.sh gaze`). The invariant: **an NPC is always either looking at
(and, when it can, shooting) a threat, or watching its doors; never a wall, never with its back to a known threat.**

`Character.movement.aim_point` is the only thing that sets facing (standing = instant snap, crouched 5 rad/s), it is never reset, and it defaults
to the world's origin. The primitives set it only as they steer; the watch stage runs after them and has the last word, and it is the one
place a threat is shot at, whichever primitive or entry phase is running.

## The stage (`Watch.apply(behavior, delta)`, run in `Behavior.apply()` right after the primitive steered, the behaviour handed in for
its primitive, params, arrival, contacts, `Combat` and `Entry`; the watch keeps no reference to it)

1. Clears `threat`; does nothing when the character `use.is_busy()` (frozen in an interaction) or the primitive keeps its own gaze (`_own_gaze`): it is `melee` / `interact` /
   an `engage` that has arrived (those aim at their own target), a `throw` whose grenade is not yet away (`Combat`'s `throw.stage`: taking
   it in hand and throwing it, aimed at the spot) or an `entry` in its `bang` phase (turned away from the door for the stun).
2. **Threat** (`_pick_threat(hostiles, engaged_id)`, the behaviour's `fight.hostiles` and `fight.engage_id`): the engaged contact if `visible`, else the nearest visible, else the engaged one
   as last seen, else the nearest younger than `tuning.watch.lost_gaze`. A contact that is not visible only counts when `has_line_to` its last-seen
   spot is clear (no staring at a wall because someone is behind it).
3. With a threat: `movement.aim_point` = its position **before any gate**, then `Combat.fire_at_will` (loaded gun, in `shoot_range`, clear
   line, facing settled, cooldown) and, unless the entry is crossing (`_entry.committed()`, E4), `Combat.reload_if_dry`. Steps 2 and 3 are
   `Watch.fight_threat(behavior) -> bool` (false with no threat, nothing touched), which the evade reflex also calls while it holds its spot,
   or is caught by a frag with no spot (`docs/grenades.md` G16, `domain-ai-behavior`): the watch stage itself does not run during an evade.
4. With none and `_resting` (a `hold`, a `reload`, a `move` that has arrived and is not covering a room, a `throw` whose grenade is
   away, a `defend` or `ambush` that has arrived): `Watch.idle_gaze`, but for a `defend` or `ambush` whose params carry `door_pos`, which
   eases the gaze onto it (`Watch.ease_gaze` at `tuning.coverage.look_rate`): a defender's gun on its own doorway (`docs/leadership.md` D2), an
   ambusher's on the threshold it waits on (LD15). An ambusher at its post is primed (LD15, D37: the controller's reflexes, not this
   module): its sight tests the cone every frame and its body moves after every other, so this stage sees an entrant on the frame its step
   opens the line and fires then, with no change here.
   `gaze` (`threat` / `doors` / `primitive`, `evade` while the behaviour evades) and `threat` are the watch's, in `debug_state()["gaze"]`.

## Watch (`watch.gd`, a `RefCounted` built in `Behavior.setup`, handed the NPC's tuning there: `setup(loco, perception, tuning)`)

It holds the NPC's body from one `bind(character)` (from `Behavior.bind`); only the static `ease_gaze` takes a character.

- `apply(behavior, delta)` — the stage above; `threat` and `gaze` are what it set this tick. `_pick_threat` is its pick (`tuning.watch.lost_gaze`, 2 s).
- `fight_threat(behavior) -> bool` — the stage's threat half (steps 2 and 3), shared with the evade reflex's hold.
- `travel_point()` — where a walker looks: the farthest point, up to `tuning.watch.look_ahead` (150 px) down the walk
  the nav agent was just given (`Locomotion.path_ahead()`), sampled every 30 px, that it has a clear line to (`has_line_to`); INF with
  none. `Behavior.errand.aim_move`'s default branch and `Entry.sweep.aim_travel` use it and fall back to the steering vector. (The next waypoint
  alone hugs the door jamb, so facing it looks at the jamb.)
- `idle_gaze(delta)` — turns among `perception.entry.room_doorways(room)` (outer doors included; each with a clear line and not
  under 60 px), nearest first on entering a room then round the NPC by angle, `tuning.watch.door_dwell` (2.5 s) apiece, eased at
  `tuning.coverage.look_rate` from the actual facing. Nothing outdoors or with no door in line; an unset `movement.aim_point` (ZERO) becomes
  "where the body points". `reset()` on every new order.

## Around the stage

- `Behavior.errand.apply_move`: an arrived move zeroes `movement.move_input`, so the NPC stands still while the next decision is in flight.
- `errand.apply_hold` / `fight.apply_reload` do not aim; the stage does. `update_known` retargets a fight from a contact it has lost sight of to
  another hostile in view.
- `gait.should_run`: false while `Combat.can_fire_at(threat)` or `Combat.reload_due()`, unless the leaf has `run_through_fire` (the RETREAT
  node). A running character can neither shoot nor reload.
- `Combat`: `can_fire_at`, `reload_due`, `faces`; `peek_cover` shoots only once facing, ducks only after a shot or an empty click
  (not after a refused shot); `ambush` waits for the facing.
- `Entry`: `state.gaze_held` (set from the watch's `threat` each tick) makes `sweep.look_toward` report "settled", so a pie step the gaze cannot settle on
  because of a threat does not hold the entry. Every gaze turn goes through one static, `Watch.ease_gaze(character, point, rate, delta)`
  (the doors here, `Entry.sweep.look_toward`, `SearchCoverage.step`): it eases from the actual facing, not a private angle, so the gaze
  does not snap back when a threat lets go. `hostile_in_view` (set from the same `threat` plus a line of fire, the behaviour's `entries._hostile_in_view`)
  stops the pie and a follower's crossing while the watch stage fires; the entry crosses once it is false (`domain-ai-entry`, E14).

## Tunables (the NPC's `tuning.watch`)

`look_ahead`, `door_dwell`, `lost_gaze`, read live by `Watch` (no copy kept; its gaze's turn rate is `tuning.coverage.look_rate`). `Behavior` reads `tuning.watch.lost_gaze` too, for its own read of a threat out of sight (`entries._hostile_in_view`).

## Tests

`tests/ai/gaze/gaze_hold_watches_doors`, `gaze_fresh_npc_keeps_its_facing`, `gaze_arrival_stops` (Von answers held back by `latency_frames`),
`gaze_walk_looks_ahead`, `gaze_search_turns_to_threat`, `gaze_travel_watches_threat`, `entry_guard_fires_from_outside`,
`fire_dry_gun_on_move_reloads`, `combat_waits_for_facing` (`Combat` driven with fakes), `engaged_retargets_to_visible` (`Behavior` driven
with fakes), `ai_runs_to_destination` (W6), `retreat_keeps_running`; helper `tests/_ai/gaze_probe.gd`. A held NPC needs a look direction
to see a target at start (a starting `facing`, e.g. `Flank.npc`'s `opts.look_at`): an unset `movement.aim_point` looks where its body points.
