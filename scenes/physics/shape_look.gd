class_name ShapeLook extends RefCounted
## How `Deformation.draw_shape` draws a dented primitive shape (furniture, a character's round
## parts): its colours, the damage it shows, its art and whether its hit marks are drawn with it.
## Whoever draws the shape fills it; a field left alone takes its default.

## The fill colour, darkened by `damage_total` (unused with a `texture`).
var fill: Color = Color.WHITE
## The outline colour; the cracks derive from it when `crack_color` is left alone (no outline is
## drawn with a `texture`).
var outline: Color = Color.WHITE
## The damage the body has taken, which darkens it (`Deformation.darken`).
var damage_total: float = 0.0
## The radiating cracks' colour; `Deformation.NO_COLOR` = the outline darkened.
var crack_color: Color = Deformation.NO_COLOR
## The bullet holes' colour; `Deformation.NO_COLOR` = the default hole colour.
var hole_color: Color = Deformation.NO_COLOR
## The faint scorch halo's colour (its alpha is PhysicsDeformLookConfig's); `Deformation.NO_COLOR` =
## black.
var scorch_color: Color = Deformation.NO_COLOR
## The art spanning the shape's footprint, drawn through the dented silhouette instead of the fill
## and outline (null = filled and outlined).
var texture: Texture2D = null
## How far the art is turned within the (unturned) silhouette, radians: a round body facing any way.
var texture_angle: float = 0.0
## Whether the hit marks are drawn too; false leaves them to the caller (`Deformation.draw_marks`),
## to draw over parts layered on top.
var marks: bool = true
