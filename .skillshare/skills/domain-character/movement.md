# Character movement: posture, running, stun

All of it is the `movement` component's (`character_movement.gd`) except the turning of `facing`, which stays on `character.gd` (`_turned_toward`). Tests: `tests/character/` (`posture_*`, `run_*`, `stunned_*`).

## Posture (spec `docs/cover-and-stance.md` P1 to P6, A1 to A3)

A character is standing or crouching (`movement`'s `_posture`, a `CharacterPostureConfig.postures` key). `CharacterStanceConfig.stances` is how a *hand* is held; the body is a *posture*.

- API (interface 7): `movement.set_posture(p) -> bool` is idempotent, so a controller may write it every frame; it is refused while dead, in an interaction or within `change_time` of the last change. `toggle_crouch()` is C (`Keybinds.CROUCH` through `player_controller.gd`).
- **Controllers keep no copy of the numbers.** The AI reads `movement.posture_coverage(posture)` (the body's height on the coverage scale: what furniture must stand above to shield it), `movement.run_speed()` and `movement.walk_speed()` (as they are now: slower while stunned or weighed down), so its grenade geometry judges a spot by them. Test: `posture_and_run_reads_test`.
- Shooting, reloading and `weapon.melee()` work in every posture; `anatomy.leg_kick()` only standing; running only standing (a refused run costs no stamina). `get_surface().coverage` is the posture's row.
- Starting an interaction stands the character up (`movement.stand_up()`) and locks the posture. `_die` stands it (after taking the momentum), so a body falls from the standing skeleton. The collision circle and `radius` never change.
- Only `facing` is slowed by the posture's `turn` rate; `movement.aim_point` never is, so hands, weapon and shots follow the slower body.
- The drawn body eases into the pose (`posture_ease`, read through `movement.posture_height()`, `posture_folded()`, `posture_hand_ahead()`); the fold itself is `body.md`. Its height is `BodyHeights.height_share(body_posture())`, the pose's head top over the stature (a crouch is the duck's 36 of 74: there is no `height` column), so mesh, twin and sight agree.
- **`movement.body_posture()`** is the real pose (`BodyHeights`): stand, the duck (crouching), or the pose a ducked body has risen to fire from (`weapon.rise.pose()`). The twin, hit zones, eye (`SightRay`), muzzle (`weapon.muzzle_height()`) and the drawn height all follow it; `posture()` stays `stand` / `crouch` (speed, run, turn, the AI's A1/A2).
- **Rise to fire (P6).** `weapon.rise` (`character_rise.gd`, `CharacterRise`: state `_pose`, `_wait`, `_dwell`; tick by `movement.tick`; dropped by `set_posture`, `stand_up`): `weapon.shoot()` of a gun by a crouched body asks `rise.pose_needed(hand)` (the duck's muzzle line cast 3D into the twin space for `CharacterRiseConfig.reach`, the struck part's top through `TwinShapes.top_of_shape`, `BodyHeights.lowest_clearing`, recast from each higher pose across `cover_depth`) and `rise.rise_to(pose)`; the shot waits `rise_time`, the pose drops `dwell` after the last ask. `weapon.rising()`-style reads: `weapon.rise.rising()`; the player's click waits for it (`player_controller._click_wait`). Tuning: `CharacterRiseConfig` (`reach`, `cover_depth`, `rise_time`, `dwell`). Tests: `rise_over_sofa`, `rise_to_stand_over_tall_cover`, `no_rise_behind_unclearable_cover`, `risen_body_is_exposed`, `risen_body_sees_over_cover`, `crouch_draws_the_duck`.

## Running and stamina

A controller sets `movement.run_input` (the player: `Keybinds.RUN`, Shift; an NPC: its behaviour layer). Each frame on foot `walk` (or, held still, `hold`) runs `_update_stamina`, which decides `_running` (asked, moving above `run_min_input`, not exhausted) and spends or refills the 0..1 `stamina`. Running dry latches `_exhausted`: the character walks, run still held, until the bar refills to `run_resume_fraction`. Details to keep in mind:

- `_move_speed()` multiplies the pace by `run_speed_mult` while running and is also used for the death momentum and the push carry cap.
- The pose's drive carries the walk `movement.speed` as `top_speed`, so the walk amount stays 1 while the stride cadence rises with the speed.
- `weapon.shoot()` does nothing while running (`weapon.melee()` still works). Being busy in an interaction counts as not running.
- The outfit's weight slows every pace and spends stamina faster (`wardrobe.md`).
- Reads: `movement.is_running()`, `stamina_fraction()`. The run's pose is `body.md`.

## The stun on the walk (spec `docs/grenades.md` G13)

While `stun.level()` is above 0, `_move_speed()` scales to `CharacterStunConfig.speed`, running is refused and the walk drifts (`stun.drift()`). The stunned look and one-handed fire are `weapon.md` and `body.md`.
