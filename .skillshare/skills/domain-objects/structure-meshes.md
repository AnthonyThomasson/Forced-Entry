# The building's 3D meshes (`scenes/objects/art/structure_meshes.gd`, interface 27)

Hooked by kind, not art id (`structure_meshes.gd`, `StructureMeshes`: `ObjectMeshes.register` calls it): `wall_mesh.gd` (every wall segment its own
`Segment<i>` instance at its collider's footprint, `wall_height` 96, the doorways open; `Wall.segment_shapes()` is what it reads, so a hit wall's rebuilt colliders re-mesh it through
the mirror and a dented segment is built from the convex pieces), `door_mesh.gd` (`DoorMesh`: the leaf at the 2D leaf's size, `door_height` 84, a handle, glass panes; the swing is the
body's transform, a knocked-down door and shattered panes are its `mirror_update`), `floor_mesh.gd` (a flat slab level with the ground, no shadow) and `street_mesh.gd` (registered
under `MirrorProxy.floor_key("street")`: the pavement level with the floors and a kerb band, the road `kerb` px lower with the lane's dashes and the junctions' zebra bars and stop
line laid flat; wear, glyphs and slab joints are not modelled). Tuning: `ObjectStructureMeshConfig` (walls, doors, floors), `ObjectStreetMeshConfig` (the street). Tests:
`tests/objects/structure_mesh_test.gd`, `structure_mesh_windowed_test.gd` (`STRUCTURE_SHOT_DIR=<dir>` saves pictures).
