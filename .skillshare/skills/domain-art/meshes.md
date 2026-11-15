# Meshes: how a domain gives its things a 3D mesh (`scenes/art/mesh/`, interface 12 and 27)

The 3D render (#193, ADR 0013) shows every 2D body by a proxy box until its domain gives it a mesh. Each domain owns its meshes, as it
owns its painters: the builders live **beside the painters** (`scenes/objects/art/table_mesh.gd`), built from Art's **mesh kit**, and the
domain plugs them into the mirror's hook. The pattern, proved on the table (`ObjectMeshes`, `TableMesh`, `ObjectMeshConfig`,
`tests/objects/table_mesh_test.gd`), is what every per-domain job copies.

## The parts

| Part | Role |
|---|---|
| `MeshKit` (`mesh/mesh_kit.gd`) | A chain of solids, one `ArrayMesh` from `build()`: `box`, `wedge` (a ramp or headboard), `cylinder`, `extrude` (a 2D polygon and a height: a rounded top, an L-shaped counter; a prism is a triangle extruded), `loft` (a convex profile swept along a path: a rail, a pipe, a roofline). Flat-shaded, one colour per face in the vertex colour. |
| `MeshCache` (`mesh/mesh_cache.gd`) | `MeshCache.fetch(MeshCache.key(id, size, color, opts), make)`: the same inputs give the same `Mesh` resource, shared by every piece, as `PixelArt` shares a texture. **The key must name every input the shape reads:** `opts` holds the piece's options and every tuning value the builder reads (`TableMesh._tuning()`), so a retuned holder is another mesh; the scale (`RenderConfig.unit`) is in the key already. |
| `MeshNodes` (`mesh/mesh_nodes.gd`) | `instance(mesh, tint)` a `MeshInstance3D` in the shared toon material; `place(node, at_px, yaw)`; `surface_frame` and `decal` (a flat quad, textured or plain, laid on a surface: wear, stencils, stains; its material is `ToonMaterial.decal(texture)`, one per texture, retuned with the shared one). |
| `MeshKitConfig` | `cylinder_sides`, `decal_lift`. |
| `ToonMask` (`post/toon_mask.gd`) | Phase 3's vision hook (`mesh-hook.md`): not for a mesh job to touch. |

## Units: px in, 3D units out, converted once

A builder works in the art's own units and **never multiplies by `RenderConfig.unit`**: `MeshKit.build()` converts, `MeshNodes.place` and
`decal` convert. A footprint is in 2D px (`x`, `y` of the piece's frame, `y` down the screen) and a height in px above the ground:
`MeshKit.volume(footprint, base, height)` is the box `(x, base, y)` to `(x + w, base + height, y + d)`; 2D `(x, y)` is 3D `(x, height, y)`.
A builder's node is in the **body's frame**: its origin is the body's origin (a piece's footprint is centred on it: `Rect2(-size / 2, size)`),
and the mirror turns it with the body (a 2D turn clockwise is `-angle` about +y; the mirror does it).

## Colour: a tone from the ramp, banded by the material

A face carries a colour; the toon material (`ToonMaterial`) multiplies it by the instance's tint (white: the mesh's own colours) and does the
banding by the light. So a face never darkens itself for the light: it carries the **base colour of its part**, and a different tone only to
tell parts apart (`MeshKit.tone(base, &"dark")` is `ArtSurfaceConfig.tones(base)["dark"]`): the table's top is the painter's colour, its
sides a darker tone, its legs the shadow tone. The base colour is the one the painter draws in: `ObjectArt.drawn_color(piece.color)` (the
run-down grade), so the 3D and the 2D match. A face's finish (wood, fabric, metal) is a choice of its colour for now (the shader has no
finish term); a vertex colour is the whole of what a face carries.

## Registering a builder

1. Write `static func build(body: Node2D) -> Node3D` beside the painter: read the body's data (`size`, `color`, `look.art_opts`), build the mesh
   through `MeshCache.fetch` (key = id + footprint + colour + the options that change the shape), return `MeshNodes.instance(mesh)` (a node
   with child nodes for parts that move: a door's leaf, a wheel).
2. List it in the domain's registry (`ObjectMeshes.BUILDERS`: art id -> script) whose `register(builders)` puts each under its hook key.
3. Main's `main_view3d.gd` `_register_meshes()` calls the domain's `register(mirror.builders)` (Main knows every domain; Art never imports
   one). Nothing else changes: a body with no builder keeps its proxy, and the builder returning null does too.

**The hook keys, floors, drawn things that are no physics body** (`track`, `track_group`: a domain's spawner only `add_to_group`s and Main's `_register_meshes()` tracks the group) and
the rules the mirror follows: `mesh-hook.md`. A finer key is for one art id (`MirrorProxy.furniture_key("table")`) and wins over the `FURNITURE` kind.

## Heights (px; a standing character is 58, a wall 96: `MirrorConfig`)

Plausible, not exact; one number per class, tuned at the phase gate in the game, kept in the domain's own holder (`ObjectMeshConfig`).

| Class | Height | Class | Height |
|---|---|---|---|
| Wall | 96 (`MirrorConfig.wall_height`) | Door leaf | 84 |
| Character standing | 58 | Character crouched | 38 (the cover posture, `docs/cover-and-stance.md`) |
| Table, desk, bench top | 30 (top 4 thick) | Coffee table, side table | 18 to 22 |
| Chair seat / back | 18 / 36 | Sofa seat / back | 18 / 38 |
| Bed frame / mattress top | 14 / 22 | Counter, island | 34 |
| Shelf, cabinet, wardrobe | 70 to 80 | Fridge, vending machine | 70 |
| Toilet, bath rim | 20 | Plant | 30 to 40 |
| Streetlight post | 130 | Car body / roof | 36 / 52 |
| Rug, mat, floor stencil | 0.5 (a decal, not a solid) | Dropped item, casing | 2 to 6 |

A tall solid (a wall, a wardrobe) hides what is behind it: the wall-fade job (rule 9) fades those near the player, so a mesh job does not shorten a
wall to keep the view clear.

## Tests

A pure builder question (a solid's size, a face's colour and winding) is a native suite on the kit (`tests/art/mesh_kit_suite.gd`); a domain's mesh is a
`GameTest` that mirrors a body with `ObjectMeshes.register(mirror.builders)` and asserts the mesh the body is shown by: its size from the piece's own data
and the how-to's height (a copy of the spec's number, as `table_mesh_test.gd` keeps), its colour, that two pieces alike share one `Mesh`, and half the size at
`RenderConfig.unit = 0.5`. What the picture looks like is only judged in a window: `tests/objects/table_mesh_windowed_test.gd` (`MESHKIT_SHOT=<png>` saves it)
is the one to copy; shaders compile only windowed (`art/toon_vision_hook_windowed`).
