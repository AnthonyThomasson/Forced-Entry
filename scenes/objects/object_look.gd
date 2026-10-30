extends RefCounted
## Objects domain (private): a piece's look, `piece.look`, what its visuals draw: the painter id,
## its options, its facing and the flat label's colour. Plain data, filled by `ObjectFactory` from
## the catalogue definition and read by the piece's visuals, its overhang and its lights.

## Pixel-art painter id ("sofa", "table", "chair"); "" draws the flat shape and its label.
var art: String = ""
## Per-piece painter overrides (see the ObjectArt*Config holders), e.g. { "inset": true }.
var art_opts: Dictionary = {}
## Which way the piece's front faces, in its local frame (a cardinal direction). Visual only:
## it orients the art (a sofa's seat, a chair's seat away from its back rail).
var facing: Vector2 = Vector2.DOWN
## Label color.
var text_color: Color = Color.WHITE
