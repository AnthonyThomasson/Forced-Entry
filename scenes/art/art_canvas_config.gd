class_name ArtCanvasConfig
## What every procedural pixel-art painting shares (Art domain, scenes/art/): the art pixel's size,
## where the light falls from, the turn steps freely turning art is lit at, and the drop and cast
## shadows. How a surface is shaded is `ArtSurfaceConfig`; each domain keeps its own painters'
## proportions and colors in its own config.
##
## A `class_name` holder of `static var`s, read as `ArtCanvasConfig.<name>`; there is no instance
## and no autoload.

## World px per art pixel (1 = one art pixel per world px; 2 = chunkier pixels, less detail).
static var pixel_size: float = 1.0
## World-space direction the light comes FROM (top-left). Edges facing it are highlighted,
## edges facing away are shaded, and raised parts cast shadows away from it.
static var light_from: Vector2 = Vector2(-1.0, -1.0)
## Lighting steps for freely turning art (characters, held items): the art is painted lit at this
## many evenly spaced angles and drawn rotated to the exact one in between.
static var turn_steps: int = 16
## Drop shadow on the floor, offset away from the light by a piece's height proxy: px per point
## of `coverage` (0 = none), capped at drop_shadow_max; and its opacity. Non-solid decor casts none.
static var drop_shadow_per_coverage: float = 0.06
static var drop_shadow_max: float = 6.0
static var drop_shadow_alpha: float = 0.28
## How far (art px) a raised part (a sofa arm, a chair's back rail) shades the lower surface
## beside it, and how much it darkens it.
static var cast_shadow_px: int = 2
static var cast_shadow_darken: float = 0.22
