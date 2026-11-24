# Blood's landing in 3D (`blood_landing.gd`, `domain-physics`)

`blood_landing.gd` (`BloodLanding`): Where a parcel of blood thrown at a hit's real height comes down in the twin 3D space: 8 ray segments (sorted queries, no contact events) along its fall; a wall's face, a piece's top or `{}` (the floor).

`BloodWound.record` traces each spray splat and the exit splat as a parcel that leaves at `hit.height` (real px; -1, a blast, skips it) and
flies the splat's reach (`BloodSprayConfig.reach_min..reach_max` px out; the exit blood `reach_max`; the one at the wound, none) along its throw, falling (`BloodLanding.trace`, through `TwinSpace.space_of`). A wall met first is marked at the height the parcel
reaches it (a chest-height hit beside a wall stands on the wall near that height), a piece's top is marked at its real height (a desk's 31 px), both through
`BloodThrow.surface`: the splat sits at that point, is not clipped by the 2D walls round it, is not in `BloodField` (no footprint or wetness reads it), and
`InkFx` stands it on the wall's face (its x along the wall, its y down it from the struck height, cut off at the floor and at `PhysicsInkConfig.wall_top`; face normals, `InkMark.normals`)
or lays it flat at the top's height. A parcel that meets nothing lands as before. Known limits: a top or wall splat is not cut at the edge of its top or wall (a corner, a doorway);
drips and the bleed-out pool stay floor-only; the splat's plan polygon is what is stood up. Test: `blood_marks_the_wall_at_hit_height_test.gd`.
