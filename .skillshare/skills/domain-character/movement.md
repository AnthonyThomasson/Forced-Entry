# Character movement: posture, running, stun

All of it is the `movement` component's (`character_movement.gd`) except the turning of `facing`, which stays on `character.gd` (`_turned_toward`). Tests: `tests/character/` (`posture_*`, `run_*`, `stunned_*`).

## Posture (spec `docs/cover-and-stance.md` P1 to P6, A1 to A3)

A character is standing or crouching (`movement`'s `_posture`, a `CharacterPostureConfig.postures` key). `CharacterStanceConfig.stances` is how a *hand* is held; the body is a *posture*.

- API (interface 7): `movement.set_posture(p) -> bool` is idempotent, so a controller may write it every frame; it is refused while dead, in an interaction or within `change_time` of the last change. `toggle_crouch()` is C (`Keybinds.CROUCH` through `player_controller.gd`).
- **Controllers keep no copy of the numbers.** The AI reads `movement.run_speed()` and `movement.walk_speed()` (as they are now: slower while stunned or weighed down), so its grenade geometry judges a spot by them (a posture's height is `BodyHeights`', real px). Test: `posture_and_run_reads_test`.
- Shooting, reloading and `weapon.melee()` work in every posture; `anatomy.leg_kick()` only standing; running only standing (a refused run costs no stamina).
- Starting an interaction stands the character up (`movement.stand_up()`) and locks the posture. `_die` stands it (after taking the momentum), so a body falls from the standing skeleton. The collision circle and `radius` never change.
- Only `facing` is slowed by the posture's `turn` rate; `movement.aim_point` never is, so hands, weapon and shots follow the slower body.
- The drawn body eases into the pose (`posture_ease`, read through `movement.posture_height()`, `posture_folded()`, `posture_hand_ahead()`); the fold itself is `body.md`. Its height is `BodyHeights.height_share(body_posture())`, the pose's head top over the stature (a crouch is the duck's 36 of 74: there is no `height` column), so mesh, twin and sight agree.
- **`movement.body_posture()`** is the real pose (`BodyHeights`): stand, the duck (crouching), or the pose a ducked body has risen to fire from (`weapon.rise.pose()`). The twin, hit zones, eye (`SightRay`), muzzle (`weapon.muzzle_height()`) and the drawn height all follow it; `posture()` stays `stand` / `crouch` (speed, run, turn, the AI's A1/A2).
- **Rise to fire (P6).** `weapon.rise` (`character_rise.gd`, `CharacterRise`: state `_pose`, `_wait`, `_dwell`; tick by `movement.tick`; dropped by `set_posture`, `stand_up`): `weapon.shoot()` of a gun by a crouched body asks `rise.pose_needed(hand)` (the duck's muzzle line cast 3D into the twin space, the struck part's top through `TwinShapes.top_of_shape`, `BodyHeights.lowest_clearing`, recast from each higher pose along the whole run: no reach limit, D7b) and `rise.rise_to(pose)`; the shot waits `rise_time`, the pose drops `dwell` after the last ask. Only a gun that `can_fire()` rises; the dwell is at least its `fire_interval()` plus `dwell_margin`. `rise.pose_along(direction, run, aim_height)` is the one rule (the AI gate reads it too); `weapon.rise.rising()`; the player's click waits for the rise (`player_controller._click_pending`, void if the rise is dropped). Tuning: `CharacterRiseConfig` (`rise_time`, `dwell`, `dwell_margin`). Tests: `rise_over_sofa`, `rise_to_stand_over_tall_cover`, `no_rise_behind_unclearable_cover`, `risen_body_is_exposed`, `risen_body_sees_over_cover`, `crouch_draws_the_duck`, `rise_click_waits`, `rise_ends`, `no_rise_when_gun_cannot_fire`, `rise_line_matches_rise`.

## Running and stamina

A controller sets `movement.run_input` (the player: `Keybinds.RUN`, Shift; an NPC: its behaviour layer). Each frame on foot `walk` (or, held still, `hold`) runs `_update_stamina`, which decides `_running` (asked, moving above `run_min_input`, not exhausted) and spends or refills the 0..1 `stamina`. Running dry latches `_exhausted`: the character walks, run still held, until the bar refills to `run_resume_fraction`. Details to keep in mind:

- `_move_speed()` multiplies the pace by `run_speed_mult` while running and is also used for the death momentum and the push carry cap.
- The pose's drive carries the walk `movement.speed` as `top_speed`, so the walk amount stays 1 while the stride cadence rises with the speed.
- `weapon.shoot()` does nothing while running (`weapon.melee()` still works). Being busy in an interaction counts as not running.
- The outfit's weight slows every pace and spends stamina faster (`wardrobe.md`).
- Reads: `movement.is_running()`, `stamina_fraction()`. The run's pose is `body.md`.

## The stun on the walk (spec `docs/grenades.md` G13)

While `stun.level()` is above 0, `_move_speed()` scales to `CharacterStunConfig.speed`, running is refused and the walk drifts (`stun.drift()`). The stunned look and one-handed fire are `weapon.md` and `body.md`.

## The 3D body (`CharacterTwin`, interface 29, D13)

a character's twin is a `CharacterTwin` (`character/character_twin.gd`, a `CharacterBody3D`, an upright cylinder the radius of the body's circle and the height of its posture: `BodyHeights`
  STAND, DUCK or the pose a rise took), the truth of where it stands; the character itself, a plain `Node2D` plan handle with no 2D shape or layer, is the footprint written from it. `CharacterMovement.walk` moves it (`TwinSpace.walker_of(body) -> CharacterBody3D`, null for a body
  with no such twin, whose 2D `move_and_slide` still runs): `move_and_slide` in 3D, floating mode and `y` held at 0 (the body is locked upright on the floor: a piece is an obstacle, never a step; its feet stand 0.5 px up, over a floor slab and
  a kerb), `wall_min_slide_angle` 3 degrees (a body that meets a wall nearly square stops, one a few degrees off slides, as the 2D body did), against `TWIN_BLOCKS` (`TWIN_WORLD`, `TWIN_VEHICLE` and the other `TWIN_CHARACTER`s; a door lying flat is on `TWIN_WALKOVER`, which the walker crosses). What it slid into that takes a shove (`contacts()`: the slide's own motion queries, the pushables only, one per body, ordered by where they stand, never Jolt's contact events or lists, which are not deterministic run to run) is
  shoved through `Knockback.push` (5) at hip height by the walk (`CharacterMovement._apply_pushes`), so a free piece is pushed as a `PieceBody` and a heavy one holds the walker. `TwinSpace.real_velocity_of(body: Object) -> Vector2` is the plan velocity a
  body covered (the 3D body's for a led character, `get_real_velocity()` for any other): what the nav, the footsteps, the pose and the gaze read in place of the 2D body's own. A 2D transform moved by a script, a door's nudge, a vehicle's strike or a
  ride is adopted (`CharacterTwin.follow`, the twin space's `_follow_lead` hook: the 3D body is put there, velocity zero) so a door (24) and a vehicle (19), still 2D-led, reach it. A stance change resizes the cylinder (`twin_update`); a stand-up or a rise
  that would grow it into a solid of the world or a vehicle (a shelf, a piece lying across it) is refused (`CharacterMovement.has_room_for(pose)`, `CharacterTwin.fits`; the rise stays ducked and its round meets the cover). The legs, the fists and the kick
  are cast and struck in 3D at their real heights (`character/body/body_sweep.gd`, `body_strike.gd`; `BodyHeights.contact` hip, fist, leg, knee, ankle), a free piece shoved at the point and height it is struck.
  A character holding a sleeping body (`hold`, a leaf resting on them) with no walk to make is not `move_and_slide`'d (and not depenetrated) until it walks: `docs/twins.md` T2.
  It rests `SAFE_MARGIN` (0.02 px) off what stops it, and `shift(aside, leaf)` moves it clear of a swinging leaf when nothing else stands in the way (a door's nudge); a body with no twin yet does not walk. Tests: `walk_in_3d`, `twin_capsule_rise`, `stand_under_beam`, `heavy_piece_blocks_walker`, `shove_height_in_3d`, `kick_lands_at_shin_height`, `door_nudge_reaches_3d_body`, `vehicle_strike_reaches_3d_body`.
