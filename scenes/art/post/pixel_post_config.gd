class_name PixelPostConfig
## Art domain, the pixel post of the 3D render (#193 rule 6, interface 27): how the low-resolution
## 3D picture is made to read as pixel art. A `class_name` holder of `static var`s, read as
## `PixelPostConfig.<name>` (ADR 0003); the shaders and `ToonMaterial` / `PixelPost` take their
## values from it, and the picture's own resolution is the camera rig's
## (`RenderConfig.texel_match`).

## How many tone bands the lit amount (N.L times the shadow) steps through, 2 to 5 (`ToonMaterial`
## holds it there; 0 is a smooth ramp): 3 picks the shadow, base and light tones of
## `ArtSurfaceConfig.tones`, 4 adds the dark tone, 5 every tone.
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
## The shimmer mitigation of a turning camera: the 3D picture is rendered this many times the
## picture's own size and averaged down to it before the nearest upscale. `supersample` is the
## picture at rest (1: none, the art's texels crisp and the cost of the picture itself) and
## `turn_supersample` while a quarter turn is under way (2: the turn only, about 0.4 s, when texels
## rotate under nearest sampling and an edge crawls; measured on a room turning
## (`art/pixel_post_shimmer`) it flickers about a fifth less than 1 and keeps a thin outline whole;
## a wider silhouette outline (`silhouette_px` 2) flickers more, not less). At a cardinal the art's
## texels line up with the picture's, so the average of the 2x2 samples is the texel itself and the
## switch at the ends of a turn shows no step.
static var supersample: int = 1
static var turn_supersample: int = 2


## The `(mul, lift)` of the shadow, dark, base, light and highlight tones of `ArtSurfaceConfig`
## (`tones`): a tone is `base * mul + (1 - base) * lift` (a darkened tone a multiplier, a
## lightened one a lift), in the order of the shader's `ramp`.
static func ramp() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(1.0 - ArtSurfaceConfig.tone_shadow, 0.0),
		Vector2(1.0 - ArtSurfaceConfig.tone_dark, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, ArtSurfaceConfig.tone_light),
		Vector2(1.0, ArtSurfaceConfig.tone_highlight),
	])


## Which tone (an index into `ramp()`) each band takes, darkest band first, for `count` bands: the
## shadow tone is always the floor and the base and light tones the steps above it.
static func picks(count: int) -> PackedInt32Array:
	match count:
		2:
			return PackedInt32Array([0, 2, 2, 2, 2])
		3:
			return PackedInt32Array([0, 2, 3, 3, 3])
		4:
			return PackedInt32Array([0, 1, 2, 3, 3])
	return PackedInt32Array([0, 1, 2, 3, 4])
