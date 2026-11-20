12. **Objects / Character / Items / Vehicles / World Generation → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.warm(requests) -> void` + `finish_warming() -> void` — paint complete flat request dictionaries (`{ painter, size, color, opts, facing? }`) on one worker,
	  under the cache mutex, and file their Images as textures on the main thread. A build never waits for the warm: a `render_flat` files the
	  image the worker already painted for its key, else paints it synchronously, and the worker skips a key already cached. WorldGen supplies Objects' shared-district requests at boot; headless skips the call.
    - `PixelArt.render_flat(painter, size, color, opts := {}, facing := Vector2.DOWN) -> Texture2D` + `PixelArt.emissive_flat(...)` — a painter's ALBEDO for the 3D render:
	  painted with no light (no bevel, cast shadow or glare), canonical (no facing, no angle step: one texture per piece and look), under the
	  `|flat` cache key; a `warm` request prewarms it; `facing` (a decal's) turns the picture in quarter turns. Details: the flat-paint side file of `domain-art`.
    - `PixelCanvas` — the surface a painter draws on (`static paint(canvas, base, material, opts)`): `fill`, `bevel`, `outline`, `surface`,
	  `grain`, `speckle`, `glare`, `cast_shadows` … over the shapes it is handed (a cleared shape is `fill(shape, PixelCanvas.CLEAR, 0)`);
	  `PixelCanvas.line` draws along `PixelShape.line_points(a, b) -> Array[Vector2i]` (one Bresenham line), which Objects' `art/decay.gd`
	  walks for its lines and scratches.
    - `PixelShape` (`art/pixel_shape.gd`) — the shapes: static factories `PixelShape.rounded` / `ellipse` / `disc` / `bowed` (`bowed` a
	  mask `PixelShape`; the other three `PixelConvexShape`s, `art/pixel_convex_shape.gd`, `extends PixelShape`).
	  `PixelConvexShape.new(rect, x0, x1, y0, y1)` (a shape from per-row and per-column spans) is built from outside by Vehicles'
	  `art/vehicle_art.gd`.
    - Tone: `ArtSurfaceConfig.tones(base)` is the tone ramp; `ArtSurfaceConfig.jitter(rng, col, k)` a colour's signed tone jitter (one `rng`
	  draw within `k`) which the floor, table and wall painters shift a tone by.
    - **What gives light** (a screen's face, a tube, a bulb, an LED): a painter draws it inside `canvas.glowing(draw: Callable, area :=
	  Rect2i())`, marking every pixel the drawing changes as emissive. `PixelArt.emissive_flat` returns those pixels of `render_flat`'s texture for the same inputs (same paint, cached beside it; transparent
	  elsewhere, null when nothing glows), for a mesh that glows.
    - A painter's options carry a big look (a character style's resolved look, a weapon style's colours) as an int handle, never the look
	  itself: `PixelArt.handle(look) -> int` registers it (the look's hash), `PixelArt.look_of(opts) -> Dictionary` reads `opts.look` back
	  (`{}` for none); the Character's and Items' painters and their callers use them.
    - **The mesh kit** (`art/mesh/`, the 3D render's counterpart of the painters; how-to `domain-art/meshes.md`) — each domain builds its own meshes from it, beside its painters:
      `MeshKit` (instance; works in px, `build() -> ArrayMesh` converts with `RenderConfig.unit` once): `MeshKit.volume(footprint: Rect2, base, height) -> AABB`, `box(volume, color,
      top_color)`, `wedge(volume, rises_toward: Vector2, color, top_color)`, `cylinder(at: Vector3, radius, height, color, top_color)` (`sides`), `extrude(polygon, base, height, color,
      top_color)` (a prism is a triangle extruded), `loft(path: PackedVector3Array, profile: PackedVector2Array, color)`, `sphere(at, radius, color)`, `capsule(at, radius, height, color)`, `cone(at, radius, height, color)`, `revolve(profile, at, color)`, and `pose(Transform3D)` (turns and places every solid added after it); each returns the kit; flat-shaded, a colour per face in the
      vertex colour; `MeshKit.tone(base, name)` picks a tone of `ArtSurfaceConfig.tones`. `MeshCache.key(id, size, color, opts)` + `MeshCache.fetch(key, make) -> Mesh`: the same inputs, the
      same `Mesh` (the key holds `RenderConfig.unit` and the kit's tunables; bounded by `MeshKitConfig.cache_limit`). `MeshNodes.instance(mesh, tint, casts_shadow) -> MeshInstance3D` (the shared toon material, `ToonMaterial.shared()`), `place(node, at_px, yaw)`,
      `surface_frame(at, normal, spin) -> Transform3D` and `decal(size, frame, texture, tint) -> MeshInstance3D` (a flat quad on a surface, the texture's alpha cuts it), `shade(radius, strength, lift)` (a drop-shadow patch), `batch(mesh, count, tint, casts_shadow, colored)` / `batch_place` / `batch_color(node, index, color)` (a part's own colour, when `colored`) / `batch_show` (many small parts in one draw), `MeshPool.new(batch)` (`add(owner)` / `remove(owner)` / `place(slot, frame)`: the places of a batch short-lived things take and give back, no hole, `count` in use), `textured(mesh_or_node, texture, rect_px, opts) -> GeometryInstance3D` (the 2D painters' art on a mesh: `toon_tex.gdshader`, `opts` `tint`, `casts_shadow`, `tiled`), `fade(node, amount)`, `glow(node, color, strength)`, `figure(node, on)` (a character's part: the outline draws its silhouette only).
      The mirror's hook that takes the meshes is interface 27. Reached by the domains that own a mesh (Objects, Vehicles, Character, Items' held and loose items, Projectile's tracers and casings and Physics' effects now), through the builders they register; Art imports nothing from them.
      Projectile's shots are no bodies: `ProjectileMeshes.install(parent, world) -> ShotLayer` (Main's view calls it) follows the world's `child_entered_tree` / `child_exiting_tree` for a `Projectile` and a `Casing` (by script), reads a tracer's `direction`, `height`, `max_distance`, `range_left()` and a casing's `altitude()` and `is_resting()` (it flies in the twin space, 29) duck-typed, and draws them in two `MeshPool`s: `ProjectileMeshConfig.tracer_capacity` (384) tracers and `Despawner.max_scene_objects` casings, read at install. A full pool says so once (`GameLog`); the layer is idle while nothing flies.
      Physics' effects are no bodies either: `PhysicsMeshes.install(parent, ground) -> FxLayer` (Main's view calls it; `ground` a Callable giving the road's drop, 04) is told by the 2D spawners through `PhysicsFxHook` (one check when none is installed: `chip_flew(chip)` / `chip_landed(chip)`, a chip node that reads `global_position`, `global_rotation` and `altitude()`, which `DebrisFx` follows in the air and lays where it rests) and shows chips, hit-particle bits, blood marks and pools, and a blast in pooled batches, meshes and rigs, sized by `Despawner.max_scene_objects`; idle at rest (`domain-physics/meshes.md`).
    - Tuning: `ArtCanvasConfig` (static holder: the art pixel's size, where the light falls from, the drop shadow's alpha and the cast shadows), `ArtSurfaceConfig` (tone ramp, tone jitter, surface finishes).

    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters (`items/art/`:
    a gun and a grenade painter per weapon style, police, scrap and pipe, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car,
    van, door, wheel, lamp) all render through these; Art imports nothing from other domains.
    - **Heights are real** (`BodyHeights`, interface 11): a mesh's px are the sim's px at 42.3 to a metre, so a mesh size is a real size. Objects' `PieceHeights` (interface 28) reads the same `ObjectMesh*Config` holders and mesh rules the builders do, so the mesh and the
	  height are one truth; `tests/objects/piece_heights_test.gd` builds every catalogue piece and checks its mesh against it and against the real range of metres of its kind.
