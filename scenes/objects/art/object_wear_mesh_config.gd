class_name ObjectWearMeshConfig
## Objects domain, wear and decals in the 3D render (`wear_mesh.gd`, `wall_wear_mesh.gd`;
## `domain-objects/meshes.md`): where a mark stands on a wall and how marks on the street are
## ranked. A `class_name` holder of `static var`s, read as `ObjectWearMeshConfig.<name>` (ADR 0003).
## Lengths are 2D pixels, the art's units. A floor mark lies on its floor slab and a street mark on
## its pavement or road; their heights are those surfaces' own (`ObjectStructureMeshConfig`,
## `ObjectStreetMeshConfig`), not tuned here.

## A wall mark's canvas is as long as the mark (`ObjectArtWearConfig.wall_lengths`) and this tall,
## by kind (px); the height its middle stands at over the ground, by kind (a wall is 96 tall).
static var wall_mark_height: Dictionary = {
	"peel": 18.0, "wall_stain": 16.0, "wall_crack": 30.0, "cable": 6.0,
}
static var wall_mark_at: Dictionary = {
	"peel": 40.0, "wall_stain": 62.0, "wall_crack": 48.0, "cable": 22.0,
}
## The height and the middle of a wall mark of a kind the two tables do not name.
static var wall_mark_height_default: float = 16.0
static var wall_mark_at_default: float = 48.0
## The layers decals take (`MeshNodes.decal`'s `layer`, `MeshKitConfig.decal_layer_step` px each),
## the order the 2D layer draws them in: a worn slab under a chip, both under the other marks, a
## lane glyph over those, a floor stencil over the floor's wear. Any domain's decal that lies on
## these surfaces takes one of them (a stencil: `tier_stencil`); a wall's marks are on the face,
## their own surface, at `tier_slab`.
static var tier_slab: float = 0.0
static var tier_chip: float = 1.0
static var tier_mark: float = 2.0
static var tier_glyph: float = 3.0
static var tier_stencil: float = 4.0
## The tier of a street mark by its kind; a kind not named is a `tier_mark`.
static var kind_tier: Dictionary = { &"slab": 0.0, &"chip": 1.0, &"glyph": 3.0 }
## Marks of one tier overlap (two cracks, a stain on a patch) and the 2D layer draws them in order.
## Mark `i` of `n` in a surface's draw order lies `order_fraction * i / n` of a tier higher than
## its tier, so no two share a depth and, the fraction being under one, a tier never reaches the
## next.
static var order_fraction: float = 0.9
## The street marks the street's own mesh already draws (the lane's dashes, the zebra crossings):
## not decals again.
static var street_drawn: Array = [&"dash", &"crossing"]
