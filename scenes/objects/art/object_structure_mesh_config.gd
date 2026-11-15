class_name ObjectStructureMeshConfig
## Objects domain, the 3D meshes of the building's structure (`structure_meshes.gd`;
## `domain-art/meshes.md`): how tall a wall and a door stand and how the floor, a wall's cap and a
## door's fittings are proportioned. A `class_name` holder of `static var`s, read as
## `ObjectStructureMeshConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units: the mesh
## kit converts them to 3D units in one place. The street's own numbers are
## `ObjectStreetMeshConfig`; furniture's are `ObjectMeshConfig`.

## A wall stands this high (the tallest thing: a standing character is 58), its top a lighter tone
## of the cap colour and its sides the cap colour itself (`ArtSurfaceConfig.tones` names).
static var wall_height: float = 96.0
static var wall_top_tone: String = "light"
static var wall_side_tone: String = "base"
## A floor is a flat slab this thick, sunk below the ground so nothing standing on it fights it;
## its edge is a darker tone of its colour.
static var floor_thickness: float = 2.0
static var floor_edge_tone: String = "shadow"
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
## it) and a lighter tone of the leaf's colour.
static var door_sill: float = 38.0
static var door_frame: float = 4.0
static var door_glass_thickness: float = 2.0
static var door_glass_tone: String = "highlight"
