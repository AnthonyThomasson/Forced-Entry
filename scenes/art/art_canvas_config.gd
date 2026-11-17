class_name ArtCanvasConfig
## What every procedural pixel-art painting shares (Art domain, scenes/art/): the art pixel's size,
## where the light falls from, and the shadows. How a surface is shaded is `ArtSurfaceConfig`; each
## domain keeps its own painters' proportions and colors in its own config.
##
## A `class_name` holder of `static var`s, read as `ArtCanvasConfig.<name>`; there is no instance
## and no autoload.

## World px per art pixel (1 = one art pixel per world px; 2 = chunkier pixels, less detail).
static var pixel_size: float = 1.0
## World-space direction the light comes FROM (top-left). Edges facing it are highlighted,
## edges facing away are shaded, and raised parts cast shadows away from it.
static var light_from: Vector2 = Vector2(-1.0, -1.0)
## The opacity of the living body's drop shadow patch in 3D (`CharacterShadowConfig`).
static var drop_shadow_alpha: float = 0.28
## How far (art px) a raised part (a sofa arm, a chair's back rail) shades the lower surface
## beside it, and how much it darkens it.
static var cast_shadow_px: int = 2
static var cast_shadow_darken: float = 0.22
## How much a flat (unlit, 3D) paint darkens the ring a painter outlines a shape with, in place of
## drawing it in the painter's dark outline colour (the 3D post draws the outline; this keeps a
## hint of the shape's edge, and the colour a side face reads from the edge texel).
static var flat_outline_darken: float = 0.12
