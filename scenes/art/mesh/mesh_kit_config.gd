class_name MeshKitConfig
## Art domain, the 3D mesh kit (`mesh_kit.gd`, interface 12): what the kit and its helpers share. A
## `class_name` holder of `static var`s, read as `MeshKitConfig.<name>` (ADR 0003). Lengths are 2D
## pixels (the art's units); `MeshKit.build` converts them with `RenderConfig.unit`.

## How many flat faces a round solid (`MeshKit.cylinder`) is made of when a call names none.
static var cylinder_sides: int = 12
## How far above its surface a decal (`MeshNodes.decal`) floats, so it never fights the surface's
## depth.
static var decal_lift: float = 0.15
