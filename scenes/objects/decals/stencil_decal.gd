extends Node2D
## A floor stencil's place and picture (Objects domain, `DecalFactory.stencil`): a plain node at the
## top-left of the area it covers, holding the flat texture of its words. It draws nothing; the 3D
## render lays the texture as a decal over the floor (`StencilMesh`), the mirror following this
## node's transform. No collider, no nav change, registers nothing.

## The stencil's flat picture, one texel per art pixel (`ArtCanvasConfig.pixel_size` px each).
var texture: Texture2D
