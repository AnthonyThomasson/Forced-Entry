# Body: pose, stances, rig

Specs: `docs/cover-and-stance.md` (P1 to P5 postures), `docs/grenades.md` G13 (the stunned look). Tests: `tests/character/` (`standing_body_rig_test`, `rig_is_solved_once_per_frame_test`, `run_pose_test`, `crouch_*`, `stunned_hunch_and_stagger_test`).

## Pose (`character_pose.gd`)

Layers motion over the aim, visual only. The anatomy steps `pose.update(delta, drive)` with a `PoseDrive` (`pose_drive.gd`, one per character, refilled by `_pose_drive`: `facing`, `velocity`, `top_speed`, `stances`, `punch`, `stun`) right after `move_and_slide()` (zero velocity while busy in an interaction; a dead character stops stepping it). It keeps three parts, stepped in this order:

- `arms` (`PoseArms`): each hand's stance, swing and recoil; `arms.kick(hand, strength)` is the character's `weapon.kick`.
- `gait` (`PoseGait`): the stride (walk and run), the stun as shown, the clock and phase that breath, glances and a hand's wander run on.
- `_springs` (`PoseSprings`): the damped angular springs; its static `accel` is the one spring every part steps by.

What it publishes: `head_angle`, `hand_angles[hand]`, `weapon_angle` (the character's `weapon.facing()`), `torso_angle`, `hip_angle`, `head_offset`, `torso_offset`. They chase `facing` on their own springs, head first, steady hand next, the weapon a touch behind the hand holding it, the shoulders last, so a turn ripples through the body; past its `max_lag` a part is reeled in at `lag_catch` rather than snapped, so a flick stays continuous.

- **Hips.** `hip_angle` (the feet's facing) is planted while standing, so the shoulders twist over feet that stay put (up to `hip_twist`), and follows the walking direction while walking (a backward step keeps the feet facing the aim).
- **Punch commits the body.** The fist lands about 51 px out but an arm is 38 px, so `torso_angle` includes a twist toward the punching side (`pose_punch_twist`, on top of the spring's own angle so recorded wounds stay consistent) and `torso_offset` lunges along `facing` (`pose_punch_lunge`; `head_offset` includes it).
- **The stunned look.** `drive.stun` eases into the gait's `_stun` at `CharacterStunConfig.look_ease`, so the look comes on and goes without a jump; 0 in a ride. `gait.hunch()` pitches the rig's spine; the stagger shrinks the stride to `stagger_stride`, advances the stride phase unevenly (a limp and a wander), sways the hips over the planted foot (`hip_sway`) and lolls the head, all scaled by the walk amount (nothing standing still).
- Tuning: `CharacterPoseTurnConfig`, `CharacterPoseHandConfig`, `CharacterPoseHeadConfig`, `CharacterStrideConfig.pose_*`, `CharacterMeleeConfig.pose_punch_*`, `CharacterStanceConfig.pose_recoil*`.

## Stances (how a hand is held)

`CharacterStanceConfig.stances` is a data table: name → `forward` / `lateral` (px, in the hand's pose frame from the body centre), grip `height` (body radii, for the arm IK), walk `swing`, `steady` (aim-style spring: follows the aim, only drifts), `recoil_share`, `elbow_pole`, optional `waver`. The held item picks one per hand through `Item.hand_stance(hand)` (`relaxed`, `guard`, `aim`, `support`, `reload`, `throw`; the long guns have `smg_grip` / `smg_fore`, `rifle_grip` / `rifle_fore`; `ready_grip` / `ready_fore` are the shared raised pair). Three are the character's own, never an item's: `run` (both hands while running, whatever is held), and while blind `eyes` and `one_hand` (`weapon.md`). To add a pose, add a table row and have an item name it.

Both hands of a long gun lie on one line along the barrel (hand 0 at +`lateral`, hand 1 at −`lateral`), and an arm's stretch must stay within the rig's tolerance. `CharacterWeapon._muzzle_ahead(item)` falls back to `CharacterStanceConfig.muzzle_ahead` for an item whose `muzzle_ahead()` is negative (the base `Item`), so Items never read Character's config.

## The rig (`character_rig.gd`)

Solves the body's 3D joints (local x/y plus height z) from the live pose and the hands. **`anatomy.rig()` solves once per physics frame** and hands every caller that frame the same rig; selecting a slot, taking a posture and dying drop the cached one at once, since they change its inputs. The legs layer solves its own unclamped rig (`Rig.new(character, false)`). `CharacterRig.solves` counts solves for `rig_is_solved_once_per_frame_test`. Joints by index (`HEAD`, `CHEST`, `PELVIS`, `BELLY`, `SPINE`, per side `SHOULDER`, `HIP`, `ELBOW`, `HAND`, `KNEE`, `ANKLE`; side 0/1 matches the hands) through `point(i)`, each foot's direction through `toes(i)`; `character_ragdoll.gd` re-exports the same indices. `CharacterRig.Measures` reads the character's measures once per solve. Proportions are `CharacterBodyConfig`'s, in body radii.

- The chest and shoulders sit in the pose's twisted torso frame shifted by `torso_offset`; hips and feet in its `hip_angle` frame.
- Arms are two-bone IK (`Measures._bend`) from each shoulder to the fist at the stance's grip height. If the hand is out of reach (`arm_extension` of the arm's length) its shoulder follows, up to `shoulder_reach`; past that the forearm stretches a little.
- Each ankle strides along the hips' forward in opposition to the arm on its side, lifting as it swings through; the knee is IK bent forward.
- **The ragdoll starts from this same rig**, so a body dies in exactly the pose it was drawn in.
- **Crouch.** The rig scales the hip height and the hands' grip heights by the posture height and, as the body folds, pitches the spine forward about the pelvis (the pelvis shifts back and the chest forward so it stays centred over its feet), narrows hips and feet, stands the feet ahead of the pelvis and staggers the weapon hand's foot back (`body_crouch_*`). The shoulders sprite and head are drawn at the rig's `CHEST` / `HEAD` xy, so the lean carries them with the sleeves. `movement.posture_hand_ahead()` is added to every hand's stance `forward` and to the wall-raise ray's reach, so the arms keep their reach past the leaning chest. A body folded past `FOLD_DRAW` is drawn by `_draw_lying` (`body-fall.md`).

## The run

`pose.gait.run_amount()` (0..1, smoothed from the speed past walking pace) blends the foot swing, lift and stride length from the walk's numbers to the run's (`body_run_*`, `pose_run_*`) and sinks the hips so the knees stay bent. Keep these constraints:

- **A planted foot only stays put when the stride is 2π × the foot's swing (~130 px);** shorter and the feet scurry and everything stride-locked wobbles at 3+ Hz.
- Keep the lowest hand grip ≥ ~4.1 body radii, or the arm overstretches (`arms.grip_height` adds `pose_run_hand_rise`).
- An elbow's bend lies in the plane through the shoulder, hand and pole, so `arms.elbow_pole` adds `pose_run_elbow_lift` that swings with the arm; a fixed pole would throw the elbow out sideways at one end of the swing.
- The run's shoulders are added over the torso spring (too slow to follow a stride): counter-rotation (`pose_run_sway`) goes into `torso_angle`; the lean (`pose_run_lean`) and the side shift go through `torso_offset`, so the rig, wounds and fall follow. The lean is in `head_offset` (the head leads); the side shift is added after it, so the head stays steady over the rocking shoulders.
- While `_running`, `weapon.stances()` ignores the held item and puts both hands in `run`; `stance_ease` lifts it back to aim on stopping.
