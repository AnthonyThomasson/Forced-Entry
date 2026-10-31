# Character movement: posture, running, stun

All of it is the `movement` component's (`character_movement.gd`) except the turning of `facing`, which stays on `character.gd` (`_turned_toward`). Tests: `tests/character/` (`posture_*`, `run_*`, `stunned_*`).

## Posture (spec `docs/cover-and-stance.md` P1 to P4, A1 to A3)

A character is standing or crouching (`movement`'s `_posture`, a `CharacterPostureConfig.postures` key). `CharacterStanceConfig.stances` is how a *hand* is held; the body is a *posture*.

- API (interface 7): `movement.set_posture(p) -> bool` is idempotent, so a controller may write it every frame; it is refused while dead, in an interaction or within `change_time` of the last change. `toggle_crouch()` is C (`Keybinds.CROUCH` through `player_controller.gd`).
- **Controllers keep no copy of the numbers.** The AI reads `movement.posture_coverage(posture)` (the body's height on the coverage scale: what furniture must stand above to shield it), `movement.run_speed()` and `movement.walk_speed()` (as they are now: slower while stunned or weighed down), so its grenade geometry judges a spot by them. Test: `posture_and_run_reads_test`.
- Shooting, reloading and `weapon.melee()` work in every posture; `anatomy.leg_kick()` only standing; running only standing (a refused run costs no stamina). `get_surface().coverage` is the posture's row.
- Starting an interaction stands the character up (`movement.stand_up()`) and locks the posture. `_die` stands it first, so a body falls from the standing skeleton. The collision circle and `radius` never change.
- Only `facing` is slowed by the posture's `turn` rate; `movement.aim_point` never is, so hands, weapon and shots follow the slower body.
- The drawn body eases into the posture (`posture_ease`, read through `movement.posture_height()`, `posture_folded()`, `posture_hand_ahead()`); the fold itself is `body.md`.

## Running and stamina

A controller sets `movement.run_input` (the player: `Keybinds.RUN`, Shift; an NPC: its behaviour layer). Each frame on foot `walk` (or, held still, `hold`) runs `_update_stamina`, which decides `_running` (asked, moving above `run_min_input`, not exhausted) and spends or refills the 0..1 `stamina`. Running dry latches `_exhausted`: the character walks, run still held, until the bar refills to `run_resume_fraction`. Details to keep in mind:

- `_move_speed()` multiplies the pace by `run_speed_mult` while running and is also used for the death momentum and the push carry cap.
- The pose's drive carries the walk `movement.speed` as `top_speed`, so the walk amount stays 1 while the stride cadence rises with the speed.
- `weapon.shoot()` does nothing while running (`weapon.melee()` still works). Being busy in an interaction counts as not running.
- The outfit's weight slows every pace and spends stamina faster (`wardrobe.md`).
- Reads: `movement.is_running()`, `stamina_fraction()`. The run's pose is `body.md`.

## The stun on the walk (spec `docs/grenades.md` G13)

While `stun.level()` is above 0, `_move_speed()` scales to `CharacterStunConfig.speed`, running is refused and the walk drifts (`stun.drift()`). The stunned look and one-handed fire are `weapon.md` and `body.md`.
