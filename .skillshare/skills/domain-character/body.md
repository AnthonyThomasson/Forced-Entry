# Character body (`scenes/character/body/`)

Everything that gives the character a body. `character.gd` (`SKILL.md`) owns state and physics and steps these through its `anatomy`; nothing here decides what the character *does*. The body's own tuning holders are in `body/` (`CharacterStrideConfig`, `CharacterMeleeConfig`, `CharacterPoseTurnConfig`, `CharacterPoseHandConfig`, `CharacterPoseHeadConfig`, `CharacterRagdollConfig`, `CharacterRagdollJointConfig`); it shares `CharacterBodyConfig`, `CharacterPostureConfig`, `CharacterStanceConfig`, `CharacterStunConfig`, `CharacterArtConfig`, `CharacterStyleConfig` and `CharacterRagdollFallConfig` with the root. Interfaces: 4 (`Deformable`/`Deformation`, generic `Ragdoll`), 6 (the held `Item`'s stances, `strike` and `art.held_mesh`; the `Outfit`'s `look(style)` and `revision`), 11 (`PhysicsLayers`), 12 (`PixelArt`, `PixelCanvas`, `ArtCanvasConfig`, `ArtSurfaceConfig`), 15 (`GameLog`).

**Side files:**
- Pose, stances, the rig, the run's legs and arms, the stunned look → `body-pose.md`.
- Hands, punch, kick, legs against walls → `body-melee.md`.
- Ragdoll fall and the fallen body → `body-fall.md`.
- Pixel-art painters and the resolved look (style, outfit, plates) → `body-art.md`.
- The 3D body mesh (#193) → `body-mesh.md`; the 2D art on it → `body-textures.md`.

## Files

Animate: `character_pose.gd` (+ parts `pose_springs`, `pose_arms`, `pose_gait`, `pose_drive`), `character_rig.gd`, `character_legs.gd`, `character_hands.gd`, `character_kick.gd`, `character_ragdoll.gd`; `body_sweep.gd` is the collide-and-slide the hands and legs share, `body_strike.gd` (+ `melee_blow.gd`) the melee strike the punch and kick share. Look: `body_dress.gd` (the resolved look, made by the 3D body: `BodyMesh`), `character_style.gd` (the look a style resolves to) and the painters in `body/art/`, whose flat renders the 3D body wears (`body-textures.md`). `character_base.tscn` attaches `character_hands.gd` as the `Hands` child; the rest are `RefCounted` helpers the anatomy owns. The 2D draw of the body (`character_visuals.gd` and its parts) is gone: the 3D body (`body-mesh.md`) is the only drawing.

## The anatomy (`character_anatomy.gd`)

`CharacterAnatomy`, built once with the character as `anatomy`, holds the animate parts (`pose`, `hands`, `legs`, `kick`, `footsteps`, `ragdoll` (null while alive), `deformable`, `wound`) and steps them. `attach()` (from `_ready`) finds the hands and adds the node parts. On foot `step(delta)` runs the kick, the pose (its `PoseDrive` refilled by `_pose_drive`), the legs and the footsteps; dead, it steps the ragdoll and bleeds out once settled. `hold(...)` is the frame a ride or interaction holds the body. `die()` / `fall(momentum, direction)` are death (`SKILL.md`).

**Order matters:** the pose is stepped right after `move_and_slide()` and before the `Hands` child's `_physics_process`, so hands build on this frame's pose. Pose, aim, shots and punches stay on `facing`; the pose is visual only.

## Gotchas

- **The pose is visual only** and the 3D body reads it (`body-mesh.md`); a test that wants a joint reads `anatomy.rig()` (solved once a physics frame and shared by every reader), not a node.
- **A body wholly outside the player's view** is hidden by the 3D mirror and the mask (`docs/player-vision.md`), not skipped: pose, hands, aim, footsteps and the ragdoll run in the animate layer, which gameplay reads, so a bullet hits the same zone with or without a view. Visibility bits: a living character is on `ViewLayers.MOVING` (`character.gd` `_ready`), a dead one is on `MOVING` until its ragdoll is settled and on `WORLD` after (`CharacterAnatomy.step`). Test: `vision/unseen_keeps_running`.
- **Wounds turn with the shoulders.** `take_hit` records impacts relative to `pose.torso_angle` (`Deformable.record(hit, torso_angle)`), so a dent stays on the shoulder or hand that was hit. Limbs are not dented (shots hit the body circle).
