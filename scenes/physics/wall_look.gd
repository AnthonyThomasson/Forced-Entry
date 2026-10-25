class_name WallLook extends RefCounted
## How `Deformation.draw_wall` draws a dented wall segment: how thick it is drawn, its colour and
## the repeating tile drawn along it. Whoever draws the wall fills it; a wall drawn plain leaves the
## tile alone.

## The segment's thickness, px.
var thickness: float = 0.0
## The fill colour; the outline and the crack marks derive from it.
var color: Color = Color.WHITE
## A repeating tile (x along the wall, y across its thickness) drawn through the dented polygon
## instead of the fill and outline (null = filled and outlined; the canvas item must repeat
## textures).
var texture: Texture2D = null
## The tile's length along the wall, px (0 = no tile).
var tile_length: float = 0.0
