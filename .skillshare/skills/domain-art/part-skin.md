# Many posed parts in one draw (`mesh/part_skin.gd` `PartSkin`, `mesh/mesh_part.gd` `MeshPart`, `post/toon_parts.gdshader`; interface 12)

Set each `MeshPart` of `skin.parts` (`PartSkin.new(count)`, at most `PartSkin.MOST`): an unindexed kit solid (`mesh`), `tint`, art (`texture` and its `rect` in model units, `cutout`), `visible`, `transform`.
Add `skin.node` (set its `custom_aabb`, as the mesh's vertices are the unposed solids; `MeshNodes.figure` and `moving` work on it). Call `skin.dress()` after a solid, tint, art or visibility changed and
`skin.pose()` after a transform did.

The shown parts are one surface and their art one atlas, shared by skins of the same parts; the pose is a material array the vertex shader reads, so each skin has its own material. The shader keeps the
textured toon's rules (`textured-toon.md`), part for part: change the two together. A part's basis columns must be square to one another (the normal is turned by the columns over their lengths squared).
A dressed solid and texture are never written again: what is read of them is kept on the resource (metadata), so a new look of known ones costs no readback and no per-vertex loop (about 0.5 ms for a body of 4400 vertices, 4.7 ms read cold), and goes when the resource does. The materials take `ToonMaterial.refresh_all` (`ToonMaterial.follow`).
Character's `BodyMesh` is the one user (`domain-character`). Tests: `tests/character/character_one_mesh_test.gd` (the look's data), `tests/art/part_skin_windowed_test.gd` (the picture against nodes of their own), `tests/art/part_skin_suite.gd` (what is kept and followed).
