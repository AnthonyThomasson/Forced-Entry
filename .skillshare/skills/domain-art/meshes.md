# Meshes: how a domain gives its things a 3D mesh (`scenes/art/mesh/`, interface 12 and 27)

The 3D render (#193, ADR 0013) shows every 2D body by a proxy box until its domain gives it a mesh. Each domain owns its meshes, as it
owns its painters: the builders live **beside the painters** (`scenes/objects/art/table_mesh.gd`), built from Art's **mesh kit**, and the
domain plugs them into the mirror's hook. The pattern, proved on the table (`ObjectMeshes`, `TableMesh`, `ObjectMeshConfig`, `tests/objects/table_mesh_test.gd`), every job copies; the building's structure (`StructureMeshes`: walls as one instance per segment, a door that follows its body and lies down by `mirror_update`, floors, the street) shows a kind's hook and a node that keeps itself in step (`domain-objects/art.md`). The domestic furniture (rig, cache-key suite, windowed pictures): `domain-objects/meshes.md`. A piece with moving parts (doors that swing, wheels that steer, lamps that glow, dents) is Vehicles' `VehicleMeshRig` (`domain-vehicle/art.md`): a cached hull, parts on child nodes and a `mirror_update` that sets their transforms.

## The parts

| Part | Role |
|---|---|
| `MeshKit` (`mesh/mesh_kit.gd`) | A chain of solids, one `ArrayMesh` from `build()`: `box`, `wedge` (a ramp or headboard), `cylinder`, `sphere`, `capsule`, `cone`, `revolve` (a profile turned about the vertical axis: a lathe post, a vase), `extrude` (a 2D polygon and a height: a rounded top, an L-shaped counter; a prism is a triangle extruded), `loft` (a convex profile swept along a path: a rail, a pipe, a roofline). **`pose(Transform3D)` turns and places every solid added after it**: a wheel on its side is the cylinder at the origin under `pose(Transform3D(Basis(Vector3.BACK, PI / 2), at))`, an aimed barrel or a tilted chair back the same; `pose(Transform3D.IDENTITY)` ends it. Flat-shaded, one colour per face in the vertex colour. |
| `MeshCache` (`mesh/mesh_cache.gd`) | `MeshCache.fetch(MeshCache.key(id, size, color, opts), make)`: the same inputs give the same `Mesh` resource, shared by every piece, as `PixelArt` shares a texture. **The key must name every input the shape reads:** `opts` holds the piece's options and each tuning value the builder reads (`TableMesh._tuning()`), so a retuned holder is another mesh; the scale (`RenderConfig.unit`) and the kit's own tunables (the tone ramp, `cylinder_sides`) are in the key already. Bounded (`MeshKitConfig.cache_limit`); a mesh unique to one node skips it (`mesh-hook.md`). |
| `MeshNodes` (`mesh/mesh_nodes.gd`) | `instance(mesh, tint)` a `MeshInstance3D` in the shared toon material; `place(node, at_px, yaw)`; `surface_frame` (upright and unmirrored on a wall's four facings) and `decal` (a flat quad laid on a surface: wear, stencils, stains; `layer` lifts it `decal_layer_step` more so overlaps never tie; lit and shadowed like the surface; its material goes with its last decal); `batch(mesh, count)` with `batch_place` / `batch_show` (many short-lived parts in one draw, no shadow: casings, sparks); `fade`, `glow` (`mesh-hook.md`). |
| `MeshKitConfig` | `cylinder_sides`, `decal_lift`, `decal_layer_step`, `cache_limit`. |
| `ToonMask` (`post/toon_mask.gd`) | Phase 3's vision hook (`mesh-hook.md`): not for a mesh job to touch. |

## Units: px in, 3D units out, converted once

A builder works in the art's own units and **never multiplies by `RenderConfig.unit`**: `MeshKit.build()` converts, `MeshNodes.place` and
`decal` convert. A footprint is in 2D px (`x`, `y` of the piece's frame, `y` down the screen) and a height in px above the ground:
`MeshKit.volume(footprint, base, height)` is the box `(x, base, y)` to `(x + w, base + height, y + d)`; 2D `(x, y)` is 3D `(x, height, y)`.
A builder's node is in the **body's frame**: its origin is the body's origin (a footprint is centred on it: `Rect2(-size / 2, size)`),
and the mirror turns it with the body (a 2D turn clockwise is `-angle` about +y; the mirror does it).

## Colour: a tone from the ramp, banded by the material

A face carries a colour; the toon material (`ToonMaterial`) multiplies it by the instance's tint (white: the mesh's own colours) and does the
banding by the light. So a face never darkens itself for the light: it carries the **base colour of its part**, and a different tone only to
tell parts apart (`MeshKit.tone(base, &"dark")` is `ArtSurfaceConfig.tones(base)["dark"]`): the table's top is the painter's colour, its
sides a darker tone, its legs the shadow tone. A face's colour is the painter's, `ObjectArt.drawn_color(piece.color)` (the run-down grade); a textured part wears the flat art (`textured-toon.md`). A face's finish is a choice of its colour (the shader has no finish term).

## Registering a builder

1. Write `static func build(body: Node2D) -> Node3D` beside the painter: read the body's data (`size`, `color`, `look.art_opts`; a height from the piece's own data or a rule of its size, as `TableMesh.height_of(size, art_opts)`: `art_opts.height`, else a low table for a small footprint), build the mesh
   through `MeshCache.fetch` (key = id + footprint + colour + the options that change the shape; a furniture piece: `FurnitureSpec.of(piece)` and `FurnitureMesh.fetch(art, spec, tuning, ...)`), and return `FurnitureMesh.show(piece, mesh)`: the rig wearing the painter's flat art (a bare `MeshNodes.instance(mesh)` is a plain slab).
2. List it in the domain's registry (`ObjectMeshes.BUILDERS`: art id -> script) whose `register(builders)` puts each under its hook key.
3. Main's `main_view3d.gd` `_register_meshes()` calls the domain's `register(mirror.builders)` (Main knows every domain; Art never imports
   one). Nothing else changes: a body with no builder keeps its proxy, and the builder returning null does too.

**The hook keys, floors, drawn things that are no physics body** (`track`, `track_group`: a domain's spawner only `add_to_group`s and Main's `_register_meshes()` tracks the group) and
the rules the mirror follows: `mesh-hook.md`. A finer key is for one art id (`MirrorProxy.furniture_key("table")`) and wins over the `FURNITURE` kind.
A mesh whose parts move with a pose is the character's: `CharacterMeshes.register` plugs `BodyMesh`, which `mirror_update` places between the 2D rig's joints (`domain-character`).

## Heights (px; 42.3 a metre, a character 74, a wall 96: `BodyHeights`, `MirrorConfig`)

Real sizes (`docs/research/3d-cover-heights.md`), one number per class in its domain's holder; `PieceHeights` (interface 12) reads them back (`domain-objects/heights.md`).

| Class | Height | Class | Height |
|---|---|---|---|
| Wall | 96 (`MirrorConfig.wall_height`) | Door leaf | 84 |
| Character standing | 74 (`BodyHeights`) | Character ducked | head top 36 |
| Table, desk top | 31 | Coffee table, side table | 18 / 22 |
| Chair seat / back | 18 / 36 | Sofa seat / arm / back | 18 / 28 / 38 |
| Bed mattress / headboard | 22 / 34 | Counter, dresser, cabinet | 38 (+ backsplash 6) |
| Bookshelf, fridge | 77, 74 | Vending machine | 78 |
| Toilet cistern, bath rim | 30, 20 | Plant | 36 |
| Streetlight post | 130 | Car body / roof | 40 / 60 (a van 46 / 78) |
| Rug, mat, stencil | 0.5 (a decal) | Dropped item, casing | 2 to 6 |

A tall solid (a wall, a wardrobe) hides what is behind it: the wall-fade job (rule 9) fades those near the player (`MeshNodes.fade`), so a mesh job does not shorten a
wall to keep the view clear, and a wall is its own instance, never merged with its neighbours.

## Tests

A pure builder question (a solid's size, a face's colour and winding) is a native suite on the kit (`tests/art/mesh_kit_suite.gd`); a domain's mesh is a
`GameTest` that mirrors a body with `ObjectMeshes.register(mirror.builders)` and asserts the mesh the body is shown by: its size from the piece's own data
and the how-to's height (a copy of the spec's number, as `table_mesh_test.gd` keeps), its colour, that two pieces alike share one `Mesh`, and half the size at
`RenderConfig.unit = 0.5`. What the picture looks like is only judged in a window: `tests/objects/table_mesh_windowed_test.gd` (`MESHKIT_SHOT=<png>` saves it)
is the one to copy; shaders compile only windowed (`art/toon_vision_hook_windowed`).
