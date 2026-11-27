class_name PixelPostConfig
## Art domain, the pixel post of the 3D render (interface 27): how the low-resolution
## 3D picture is made to read as pixel art. A `class_name` holder of `static var`s, read as
## `PixelPostConfig.<name>` (ADR 0003); the shaders and `ToonMaterial` / `PixelPost` take their
## values from it, and the picture's own resolution is the camera rig's
## (`RenderConfig.texel_match`).

## How many bands each light's amount (N.L times its fall-off and shadow) steps through, 2 to 5
## (`ToonMaterial` holds it there; 0 is no steps, a smooth light): the strength of band k is
## `ToonLightConfig.levels(count)[k]`.
static var bands: int = 3
## The outline's colour, and its width in picture pixels where two surfaces meet at a crease (a
## box's edge, read from the normals) and along a silhouette (read from the depth).
static var outline_color: Color = Color(0.06, 0.05, 0.08)
static var crease_px: float = 1.0
static var silhouette_px: float = 1.0
## What counts as an edge: the depth's second difference (reversed depth) and the length of the
## normals' difference between neighbours, which only draws a crease where the two neighbours are
## within `crease_gap` of one depth (a step further apart is a silhouette, and the depth draws it).
static var depth_step: float = 0.004
static var normal_step: float = 0.45
static var crease_gap: float = 0.012
## The line's colour is the colour of the surface it outlines (a silhouette: the nearer side's, a
## crease: its own pixel's) times this, `outline_color` the floor of it: near black on the world's
## walls and furniture, `figure_darken` (lighter) on a figure, so a character's outfit stays
## readable in its outline. 0 is the one `outline_color` everywhere.
static var outline_darken: float = 0.15
static var figure_darken: float = 0.35
## Whether a figure (a character's body) is creased like the rest: off, it is outlined by its
## silhouette only.
static var figure_creases: bool = false
## The picture's render scale: it is rendered this many times its own size and averaged down to
## it before the nearest upscale. `supersample` is the picture at rest and `turn_supersample` while
## a quarter turn is under way; both are 1 (none: the art's texels crisp and the cost of the
## picture itself). 2 for the turn was tried as a shimmer mitigation and flickers 1.7 to 1.9 times
## MORE than 1 on textured art (`art/pixel_post_shimmer`: averaging nearest-sampled art makes
## colours that are in no texel, and they change as the art turns), so the plain post wins; a wider
## silhouette outline (`silhouette_px` 2) flickers more, not less. The mechanism stays
## (`CameraRig.turn_oversample`, `View3D`'s larger stage) for a later, smoother mitigation.
static var supersample: int = 1
static var turn_supersample: int = 1
## The side, in texels, of one layer of the toon's texture atlas (`ToonAtlas`): a larger painted
## texture keeps a material of its own. A layer is written to the GPU whole when a texture is added
## to it, so a larger side costs more a new texture.
static var atlas_page: int = 512
