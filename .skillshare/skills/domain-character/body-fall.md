# Body: death and the ragdoll fall

Tests: `tests/character/` (`standing_body_rig_test` for death continuity, `character_ragdoll_mesh_test` for the fallen body in 3D), `tests/physics/frag_blast_pushes_test.gd` (a dead body's ragdoll thrown).

## The ragdoll (`character_ragdoll.gd`)

A humanoid on the Physics domain's generic `Ragdoll` (3D points over the floor: local x/y + height z), indices the rig's (`body-pose.md`). The rig's heights are the drawing's (a head 100 px up): `Ragdoll.height_scale` is `CharacterRig.squeeze(r)`, so each point is swept in the twin 3D space at the real height the 3D mesh draws it (`body-mesh.md`): the body falls against a wall and a tall piece, slumps over a low one (a sofa's arm, a counter) and lies on its top. The owner's own twin is excluded; people are not met.

- A rigid trunk (chest, pelvis, belly and back, shoulders, hips); the belly and back radii reach just to the trunk's surface so it lies flat on either side. Bones go to the head, elbows, fists, knees and ankles.
- Limits are in the trunk's frame (x toward hand 1's shoulder, y up the spine, z out of the chest): swing cones at the neck, shoulders and hips, and **one-way hinges** at the elbows (bend toward the front) and knees (toward the back), so no joint ever bends backward. Ranges: `CharacterRagdollJointConfig`.
- It starts exactly in the rig's pose and is launched with the body's momentum; the upper body is pushed along the blow (`CharacterRagdollFallConfig.hit_topple`), the knees buckle (`knee_buckle`), each point gets a jolt (`jitter`). The legs give out, the body topples and settles (about 2 to 3 s), then sleeps.
- Reads: `point(i)`, `torso()` (the trunk's basis), `face()`, `toes(i)` (a trunk-frame direction carried onto the bone by the shortest turn), `is_settled()`. `blast(...)` is an explosion's throw (`blast_push`).

The fallen body is shown by the 3D body mesh, which follows the ragdoll's joints once the character is dead (`body-mesh.md`); the 2D laid-out draw, trunk loft and floor shadow are gone.
