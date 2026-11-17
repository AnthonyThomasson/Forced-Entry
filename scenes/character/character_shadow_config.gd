class_name CharacterShadowConfig
## The body's shadows (scenes/character/): the living body's light occluder (an oval of depth, width
## and sides) and the fallen body's drawn floor shadow. A `class_name` holder of `static var`s, read
## as `CharacterShadowConfig.<name>`; there is no instance and no autoload.

## The living body's shadow footprint, in its radius: an oval `depth` deep along its facing
## and `width` across the shoulders (half-axes), as a `sides`-gon. A dead body casts
## none (a 2D occluder has no height: a body lying on the floor would throw a shadow as long as a
## wall's).
static var depth: float = 0.72
static var width: float = 1.05
static var sides: int = 10
## A fallen part's floor shadow shift per px of height (matches the standing drop shadow).
static var body_shadow_per_height: float = 0.03
## The living body's drop shadow in the 3D render (`BodyMesh`, `MeshNodes.shade`): a round patch of
## `shade_radius` body radii, shifted `shade_shift` radii away from the art's light (the 2D drop
## shadow's few px), `shade_lift` px over the floor (over a rug), its alpha ArtCanvasConfig's
## `drop_shadow_alpha`. The body's parts cast no shadow from the lights: a body's shadow is this,
## short and under it, whatever light (the sun, a ceiling fixture) is near.
static var shade_radius: float = 1.05
static var shade_shift: float = 0.22
static var shade_lift: float = 1.0
