extends RefCounted
## Objects domain, the 3D mesh of a floor stencil (#193 phase 2; `domain-art/meshes.md`): words in a
## hazard-stripe border painted on the floor (`DecalFactory.stencil`, a `StencilDecal` node that is
## no physics body, in the group `DecalFactory.STENCIL_GROUP`). The mesh is a decal: the node's own
## texture on a flat quad laid on the floor over the area it covers, so it reads as the 2D paint
## does, upright whichever way its building is turned. It shares the texture with the sprite, so it
## costs no second paint. It does no work of its own each frame (no `mirror_update`, no `_process`);
## the mirror follows the sprite as it follows any tracked node, one transform compare a frame, a
## write only when the sprite moved. It lies on the floor's slab
## (`ObjectStructureMeshConfig. floor_lift`) on the stencil tier of the shared decal layers
## (`ObjectWearMeshConfig.tier_stencil`, `MeshNodes.decal`'s `layer`), over every wear mark of the
## floor and the street, never at the height of one.


## The node a stencil `sprite` is shown by, in 3D units with its origin at the sprite's own (its
## top-left corner): a plain node holding the decal at the middle of the area, so the mirror's
## writes of the sprite's place move the whole.
static func build(sprite: Node2D) -> Node3D:
	var texture: Texture2D = sprite.get("texture")
	if texture == null:
		return null
	var size := texture.get_size() * sprite.scale
	var holder := Node3D.new()
	var at := Vector3(size.x * 0.5, ObjectStructureMeshConfig.floor_lift, size.y * 0.5)
	holder.add_child(
		MeshNodes.decal(
			size,
			MeshNodes.surface_frame(at),
			texture,
			Color.WHITE,
			ObjectWearMeshConfig.tier_stencil,
		)
	)
	return holder
