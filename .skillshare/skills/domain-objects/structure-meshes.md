# The building's 3D meshes (`scenes/objects/art/structure_meshes.gd`, interface 27)

Hooked by kind, not art id (`structure_meshes.gd`, `StructureMeshes`: `ObjectMeshes.register` calls it): `wall_mesh.gd` (every wall segment its own
`Segment<i>` instance at its collider's footprint, `wall_height` 96, the doorways open; `Wall.segment_shapes()` is what it reads, so a dented segment is built from the convex pieces; `WallMesh` is a node class that follows the wall's colliders itself: a hit makes the wall emit `segment_rebuilt(i)` and only `Segment<i>` is replaced (the mirror skips shape changes for it: `follows_shapes`), `segment_replaced(i, part)` says so. **A fade set on a replaced segment is gone: the wall-fade job reapplies it to the new part (keyed wall + segment index)**), `door_mesh.gd` (`DoorMesh`: the leaf at the 2D leaf's size, `door_height` 84, a handle, glass panes; the swing is the
body's transform, a knocked-down door and shattered panes are its `mirror_update`), `floor_mesh.gd` (a flat slab `floor_lift` 0.1 px over the ground, clear of the district's pavement slab, no shadow; a decal's lift stays over it) and `street_mesh.gd` (registered
under `MirrorProxy.floor_key("street")`: the pavement level with the floors and a kerb band, the road `kerb` px lower with the lane's dashes and the junctions' zebra bars and stop
line laid flat; slab joints are not modelled; wear and glyphs are decals, `meshes.md`). Tuning: `ObjectStructureMeshConfig` (walls, doors, floors), `ObjectStreetMeshConfig` (the street). Tests:
`tests/objects/structure_mesh_test.gd`, `structure_mesh_windowed_test.gd` (`STRUCTURE_SHOT_DIR=<dir>` saves pictures).

## The 2D art on the structure (#193 phase 2b; `structure_skin.gd`, `StructureSkin`)

The structure wears its painters' art, painted flat (`ObjectArt.flat` / `tile_flat`: no baked light, canonical, cached by `PixelArt` per kind and look, prewarmed by `DistrictPrewarm.structure_requests`) and laid by `MeshNodes.textured` (`domain-art/textured-toon.md`). The meshes are white where the art goes, so the tile colours them.

- **Floor** (`floor_mesh.gd`): the floor's tile (`art`, `color`, `floor_material`, `art_opts`), `tiled`, the grid laid from `-tile_offset` as the 2D floor does (neighbours sharing a `tile_from` share it). The mesh is shared by floors of a size; the material by floors of a look.
- **Street** (`street_mesh.gd`): the same for the pavement and the road slab. The kerb band, the lane's dashes and the crossings are a plain `Paint` child mesh over the slab (their colours are not multiplied by the asphalt), absent when a piece has none. The sidewalk's kerb face is its tile's edge texels, the slab joint's dark line.
- **Wall** (`wall_mesh.gd`): each segment wears the cap tile (`wall_painter`: x along the wall) over a tile laid from the segment's start, `tiled`; a wall along z wears the tile turned a quarter (`StructureSkin.wall_tile(wall, true)`, cached). The top is the cap; the face a step darker is the tile's edge texels stretched down, so the painter's flat read keeps the edge rows brick-and-mortar or plaster grain (no lit trim, no outline row: the 3D light and the post's outline draw those). A wall with no art keeps the cap colour (top lighter, sides the cap's) with no texture. A dented segment is the same tile over the convex pieces' extrusion.
- **Door** (`door_mesh.gd`): the leaf wears the door painter's flat art (`part: leaf`, the leaf's size, re-laid when the panes shatter), a knocked-down door the `fallen` part over its slab. The handle is a plain child mesh of the leaf (faded with it); a glass door's pane is white in the leaf mesh, the art draws the glass.
- **Flat reads:** the floor, door and street painters bake no light rims (their bevels and glare do nothing flat; the grout, seams and joints are texture), so only the wall painter reads `c.light == Vector2.ZERO`.
- Materials: one per tile and tiling (`ToonMaterial.textured_count()`): a district of one house look holds a handful. Draw order and tiers are unchanged: wear, stencils and street decals lie over the slab by their own lifts.

Tests: `tests/objects/structure_skin_test.gd`.
