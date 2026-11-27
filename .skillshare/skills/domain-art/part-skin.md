# Many posed parts in one draw (`mesh/part_skin.gd` `PartSkin`, `mesh/mesh_part.gd` `MeshPart`, `post/toon_parts.gdshader`; interface 12)

Set each `MeshPart` of `skin.parts` (`PartSkin.new(count)`, at most `PartSkin.MOST`): an unindexed kit solid (`mesh`), `tint`, art (`texture` and its `rect` in model units, `cutout`), `visible`, `transform`.
Add `skin.node` (set its `custom_aabb`, as the mesh's vertices are the unposed solids; `MeshNodes.figure` and `moving` work on it). Call `skin.dress()` after a solid, tint, art or visibility changed and
`skin.pose()` after a transform did.

The shown parts are one surface and their art one atlas, shared by skins of the same parts; the pose is a material array the vertex shader reads, so each skin has its own material. The shader keeps the
textured toon's rules (`textured-toon.md`), part for part: change the two together. A part's basis columns must be square to one another (the normal is turned by the columns over their lengths squared).
Character's `BodyMesh` is the one user (`domain-character`). Test: `tests/character/character_one_mesh_test.gd`.
