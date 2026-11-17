class_name CharacterShadowConfig
## The living body's shadow (scenes/character/). A `class_name` holder of `static var`s, read as
## `CharacterShadowConfig.<name>`; there is no instance and no autoload.

## The living body's drop shadow in the 3D render (`BodyMesh`, `MeshNodes.shade`): a round patch of
## `shade_radius` body radii, shifted `shade_shift` radii away from the art's light (the 2D drop
## shadow's few px), `shade_lift` px over the floor (over a rug), its alpha ArtCanvasConfig's
## `drop_shadow_alpha`. The body's parts cast no shadow from the lights: a body's shadow is this,
## short and under it, whatever light (the sun, a ceiling fixture) is near.
static var shade_radius: float = 1.25
static var shade_shift: float = 0.45
static var shade_lift: float = 1.0
## A body whose head is more than `shade_lies` radii (flat) from its feet lies, and its drop shadow
## is stretched along it, `shade_width` radii across.
static var shade_lies: float = 0.9
static var shade_width: float = 1.0
