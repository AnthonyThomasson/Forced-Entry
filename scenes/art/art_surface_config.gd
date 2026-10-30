class_name ArtSurfaceConfig
## How a painted surface is shaded (Art domain, scenes/art/): the tone ramp, the darken and
## lighten amounts applied to a piece's base color, and the material surface finishes (fabric
## weave, wood grain, brushed metal, stone flecks).
##
## A `class_name` holder of `static var`s, read as `ArtSurfaceConfig.<name>`, and of the ramp the
## tones make, `tones(base)`, and its random shift, `jitter(rng, col, k)`; there is no instance and
## no autoload.

## How far each tone of `tones` darkens (`tone_outline`, `tone_shadow`, `tone_dark`) or
## lightens (`tone_light`, `tone_highlight`) a piece's base color.
static var tone_outline: float = 0.62
static var tone_shadow: float = 0.36
static var tone_dark: float = 0.18
static var tone_light: float = 0.14
static var tone_highlight: float = 0.3
## Fraction of fabric pixels nudged a shade lighter/darker (a woven look).
static var fabric_speckle: float = 0.12
## Wood grain streaks per art pixel of plank area.
static var wood_grain_density: float = 0.018
## Chance that a plank carries a knot.
static var wood_knot_chance: float = 0.3
## Brushed-metal streaks per art pixel of metal area.
static var metal_brush_density: float = 0.012
## Fraction of stone pixels flecked lighter/darker (granite).
static var stone_fleck_density: float = 0.14


## Shade ramp around a base color, from the outline (darkest) to the highlight.
static func tones(base: Color) -> Dictionary:
	return {
		"outline": base.darkened(ArtSurfaceConfig.tone_outline),
		"shadow": base.darkened(ArtSurfaceConfig.tone_shadow),
		"dark": base.darkened(ArtSurfaceConfig.tone_dark),
		"base": base,
		"light": base.lightened(ArtSurfaceConfig.tone_light),
		"highlight": base.lightened(ArtSurfaceConfig.tone_highlight),
	}


## `col` shifted by a random tone within `k` of it, drawn from `rng` (a painter's canvas's):
## lightened by a positive draw, darkened by a negative one. A per-plank, per-tile or per-brick
## tone.
static func jitter(rng: RandomNumberGenerator, col: Color, k: float) -> Color:
	var shift := rng.randf_range(-k, k)
	return col.lightened(shift) if shift > 0.0 else col.darkened(-shift)
