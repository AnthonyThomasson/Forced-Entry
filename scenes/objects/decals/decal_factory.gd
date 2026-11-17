class_name DecalFactory
## Objects-domain factory (interface 2): turns where a decal goes and what it says (World-Gen's
## placement) into a draw-only node on the floor: no collider, no nav change, registers nothing.
## World-Gen never draws, and never touches the node's fields.
##
## `stencil` is a floor stencil: words painted in pixel stencil letters inside a hazard-stripe
## border over an area of floor (stencil_painter.gd). It is painted upright on a canvas the size of
## the area (its flat albedo), so it reads the same whichever way the building it lies in is turned.
## It is in the group `STENCIL_GROUP`.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const StencilDecal = preload("res://scenes/objects/decals/stencil_decal.gd")
## The group every stencil joins, for the 3D mirror to show them by (`ObjectMeshes.track`).
const STENCIL_GROUP := &"stencils"


## Lay a floor stencil of `spec` over `rect` (in `parent`'s space) under `parent`, named
## `decal_name`, and return it (a `StencilDecal`). `spec`: `text` the words (one to a line).
static func stencil(rect: Rect2, spec: Dictionary, decal_name: String, parent: Node) -> Node2D:
	var node := StencilDecal.new()
	node.name = decal_name
	node.position = rect.position
	node.texture = ObjectArt.flat(
		"stencil", rect.size, Color.WHITE, { "text": spec.get("text", "") },
	)
	node.add_to_group(STENCIL_GROUP)
	parent.add_child(node)
	return node
