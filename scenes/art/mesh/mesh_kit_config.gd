class_name MeshKitConfig
## Art domain, the 3D mesh kit (`mesh_kit.gd`, interface 12): what the kit and its helpers share. A
## `class_name` holder of `static var`s, read as `MeshKitConfig.<name>` (ADR 0003). Lengths are 2D
## pixels (the art's units); `MeshKit.build` converts them with `RenderConfig.unit`.

## How many flat faces a round solid (`MeshKit.cylinder`) is made of when a call names none.
static var cylinder_sides: int = 12
## How far above its surface a decal (`MeshNodes.decal`) floats, so it never fights the surface's
## depth.
static var decal_lift: float = 0.15
## How much higher each layer of decals lies (`MeshNodes.decal`'s `layer`): a decal on layer `l`
## floats `decal_lift + l * decal_layer_step` px off its surface, so what one domain draws over
## another's (a stencil over a floor's marks) is a layer more, never a tie in depth.
static var decal_layer_step: float = 0.25
## How many meshes `MeshCache` keeps: past it the one asked for longest ago is dropped (a node
## still showing it keeps it; asked for again it is built again).
static var cache_limit: int = 2048
## How much a textured mesh's side face (`MeshNodes.textured`, `toon_tex.gdshader`) is darkened
## beyond the light, so the art's stretched edge texels read as a side and not as a second top
## (1 = not at all).
static var textured_side_dim: float = 0.8
