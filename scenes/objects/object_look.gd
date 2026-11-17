extends RefCounted
## Objects domain (private): a piece's look, `piece.look`, what its mesh shows: the painter id, its
## options, its facing and its overhang. Plain data, filled by `ObjectFactory` from the catalogue
## definition and read by the piece's 3D mesh and its lights.

## Pixel-art painter id ("sofa", "table", "chair"); "" is the flat shape.
var art: String = ""
## Per-piece painter overrides (see the ObjectArt*Config holders), e.g. { "inset": true }.
var art_opts: Dictionary = {}
## Which way the piece's front faces, in its local frame (a cardinal direction). Visual only:
## it orients the art (a sofa's seat, a chair's seat away from its back rail).
var facing: Vector2 = Vector2.DOWN
## The definition's `overhang` (`{ size, reach }`), the part that reaches beyond the footprint, in
## the canonical frame; empty for none. A plain field the 3D meshes read.
var overhang: Dictionary = {}


## The area the overhang covers in the piece's frame: `overhang.size` (across x out; turned for a
## sideways facing), centred `overhang.reach` px along the facing. An empty `Rect2` for none.
func overhang_rect() -> Rect2:
	var canonical: Vector2 = overhang.get("size", Vector2.ZERO)
	if canonical == Vector2.ZERO:
		return Rect2()
	var size := Vector2(canonical.y, canonical.x) if absf(facing.x) > absf(facing.y) else canonical
	return Rect2(facing * float(overhang.get("reach", 0.0)) - size * 0.5, size)
