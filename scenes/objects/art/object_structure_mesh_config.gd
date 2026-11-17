class_name ObjectStructureMeshConfig
## Objects domain, the 3D meshes of the building's structure (`structure_meshes.gd`;
## `domain-art/meshes.md`): how tall a wall and a door stand and how the floor, a wall's cap and a
## door's fittings are proportioned. A `class_name` holder of `static var`s, read as
## `ObjectStructureMeshConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh
## kit converts them to 3D units in one place. The street's own numbers are
## `ObjectStreetMeshConfig`; furniture's are `ObjectMeshConfig`.

## A wall stands this high (the tallest thing: a standing character is 74), wearing its painter's
## tile; a wall with no art has its top a lighter tone of the cap colour and its sides the cap
## colour itself (`ArtSurfaceConfig.tones` names).
static var wall_height: float = 96.0
static var wall_top_tone: String = "light"
static var wall_side_tone: String = "base"
## A wall along z stands this much (px) taller than one along x, so where two walls meet their caps
## are not one plane (two textures z-fighting over a corner or a T).
static var wall_cross_lift: float = 0.01
## A floor is a flat slab this thick, sunk below the ground so nothing standing on it fights it; it
## wears its painter's tile (`StructureSkin`), the edge the tile's edge a step darker.
static var floor_thickness: float = 2.0
## A room's floor stands this far (px) over the ground plane, so it never fights the pavement slab
## of the district block it lies inside (both are level with the ground): thin enough to be flat,
## under `MeshKitConfig.decal_lift` so a decal still lies over it.
static var floor_lift: float = 0.1
## A door's leaf stands this high (a little under the wall), a handle at the latch end of its
## `door_handle_height`: `door_handle_length` along the leaf, `door_handle_thick` tall and standing
## `door_handle_proud` px off each face.
static var door_height: float = 84.0
static var door_handle_height: float = 40.0
static var door_handle_length: float = 6.0
static var door_handle_thick: float = 3.0
static var door_handle_proud: float = 1.5
## A glass-panel door: a solid panel up to `door_sill`, a frame `door_frame` wide round the glass
## above it, the glass `door_glass_thickness` thick (a thinner pane than the frame, so it sits in
## it); the leaf's art colours all of it.
static var door_sill: float = 38.0
static var door_frame: float = 4.0
static var door_glass_thickness: float = 2.0
