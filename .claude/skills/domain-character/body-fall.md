# Body: death, the ragdoll fall and the fallen body

Tests: `tests/character/` (`fallen_draw_order_stable_test`, `fallen_trunk_outline_steady_test`, `standing_body_rig_test` for death continuity), `tests/physics/` (ragdoll).

## The ragdoll (`character_ragdoll.gd`)

A humanoid on the Physics domain's generic `Ragdoll` (3D points over the floor: local x/y + height z), indices the rig's (`body-pose.md`).

- A rigid trunk (chest, pelvis, belly and back, shoulders, hips); the belly and back radii reach just to the trunk's surface so it lies flat on either side. Bones go to the head, elbows, fists, knees and ankles.
- Limits are in the trunk's frame (x toward hand 1's shoulder, y up the spine, z out of the chest): swing cones at the neck, shoulders and hips, and **one-way hinges** at the elbows (bend toward the front) and knees (toward the back), so no joint ever bends backward. Ranges: `CharacterRagdollJointConfig`.
- It starts exactly in the rig's pose and is launched with the body's momentum; the upper body is pushed along the blow (`CharacterRagdollFallConfig.hit_topple`), the knees buckle (`knee_buckle`), each point gets a jolt (`jitter`). The legs give out, the body topples and settles (about 2 to 3 s), then sleeps.
- Reads: `point(i)`, `torso()` (the trunk's basis), `face()`, `toes(i)` (a trunk-frame direction carried onto the bone by the shortest turn), `is_settled()`. `blast(...)` is an explosion's throw (`blast_push`).

## Drawing the fallen body (`body_laid_out.gd`)

The visuals' `laid.draw(rd, with_head, before_trunk)`; the shadow casts `parts_of(rd)`. A crouch past `FOLD_DRAW` is drawn the same way (`_draw_lying`).

- Every part is drawn from its 3D points seen from above, **sorted by height (lowest first)**, so a standing body hides its legs under the shoulders and a toppling one reveals them; lengths foreshorten as parts tip. The order carries over from the last frame (`_stack`, `_order`): a pair swaps only once their heights differ by more than `STACK_BAND`, so a limb lying across the trunk does not flicker over and under it.
- Limbs are chains of tapered capsules between the projected joints, widths per joint from `CharacterBodyConfig` (`body_arm_widths`, `body_leg_widths`, `body_shoe_widths`, `body_neck_width`), so neighbours share a joint's width. A chain draws every segment a pixel wider in its outline tone first, then the fills, so joints run together under one outline. Each fill maps a `limb_painter.gd` strip onto the capsule. Fists (`HandPainter`) turn along the forearm; the head (`HeadPainter`) to where the face looks.
- **The trunk** (`body_trunk.gd`, `BodyTrunk`: `draw(rd)`, and its slices `hulls(rd, shift)` for the shadow) is lofted from ellipse cross-sections (`ragdoll_trunk_sections`), domed at both ends. Its outline is the union of each neighbouring pair's hull, each grown by `HULL_OVERLAP`: seen edge-on neighbours share only a line and the union can come apart, flashing the torso as one small slice for a frame as the body landed. A union still in pieces falls back to the two slices' convex hull. It fills with the shirt, then maps the trunk's sides across it (`_faces` / `_face_art`: UVs from each side's projected axes), the most visible of chest, back and flank first, then the standing `BodyPainter` shoulders when the top is turned up more still (a crouch's bent back, a body upright as it starts to fall), then a 1 px outline. **The art is requested at whole pixels**: the spine's length flexes every frame, and an exact size would paint and cache a new texture each frame.
- Wounds sit on the trunk's surface where they struck (angle in the shoulders' frame, a seeded height between waist and chest) and draw with `Deformation.draw_marks` only while that patch faces the camera.
- The floor shadow is one shape per part (the trunk's is its outline), each point shifted from the light by its height (`body_shadow_per_height`), drawn opaque inside a code-built `CanvasGroup` that carries the alpha, so overlaps do not stack. Redrawing stops once the body has settled (a look change resets it: `body-art.md`).
