12. **Objects / Character / Items / Vehicles / World Generation → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.warm(requests) -> void` + `finish_warming() -> void` — paint complete `render` request dictionaries on one worker,
	  under the cache mutex, and file their Images as textures on the main thread. A build never waits for the warm: a `render` files the
	  image the worker already painted for its key, else paints it synchronously, and the worker skips a key already cached. WorldGen supplies Objects' shared-district requests at boot; headless skips the call.
    - `PixelArt.render(painter, size, color, facing := Vector2.DOWN, opts := {}) -> Texture2D` — a painter's art at a cardinal facing (the
	  image is turned): furniture, walls, floors. `opts.material` (`ArtSurfaceConfig`'s finish, `""` none) is handed to the painter as its
	  `material`, the rest as its `opts`.
    - `PixelArt.render_turned(painter, size, color, angle, opts := {}) -> Texture2D` + `PixelArt.snap_angle(angle)` — canonical art lit for
	  a snapped angle, drawn rotated by the caller to the exact one: characters, hands, guns, a vehicle's body, doors, wheels, lamps.
    - `PixelArt.TurnedLast` — the arguments of one caller's last `render_turned` call and the texture they got (`render(...)` is
	  `render_turned` answered from that call, or the plain call when `plain`): owned by the caller, one per part it draws every
	  frame (Character's `BodyDrawCache` slots).
    - `PixelArt.away_from_light(node) -> Vector2` — which way a cast shadow falls in `node`'s frame (away from `ArtCanvasConfig.light_from`),
	  for every caller that drops a shadow of its own.
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
	  Rect2i())`, marking every pixel the drawing changes as emissive. `PixelArt.emissive(painter, size, color, facing := Vector2.DOWN,
	  opts := {}) -> Texture2D` returns those pixels of `render`'s texture for the same inputs (same paint, cached beside it; transparent
	  elsewhere, null when nothing glows), for a caller that draws light sources unshaded.
    - A painter's options carry a big look (a character style's resolved look, a weapon style's colours) as an int handle, never the look
	  itself: `PixelArt.handle(look) -> int` registers it (the look's hash), `PixelArt.look_of(opts) -> Dictionary` reads `opts.look` back
	  (`{}` for none); the Character's and Items' painters and their callers use them.
    - **The mesh kit** (`art/mesh/`, the 3D render's counterpart of the painters; how-to `domain-art/meshes.md`) — each domain builds its own meshes from it, beside its painters:
      `MeshKit` (instance; works in px, `build() -> ArrayMesh` converts with `RenderConfig.unit` once): `MeshKit.volume(footprint: Rect2, base, height) -> AABB`, `box(volume, color,
      top_color)`, `wedge(volume, rises_toward: Vector2, color, top_color)`, `cylinder(at: Vector3, radius, height, color, top_color)` (`sides`), `extrude(polygon, base, height, color,
      top_color)` (a prism is a triangle extruded), `loft(path: PackedVector3Array, profile: PackedVector2Array, color)`, `sphere(at, radius, color)`, `capsule(at, radius, height, color)`, `cone(at, radius, height, color)`, `revolve(profile, at, color)`, and `pose(Transform3D)` (turns and places every solid added after it); each returns the kit; flat-shaded, a colour per face in the
      vertex colour; `MeshKit.tone(base, name)` picks a tone of `ArtSurfaceConfig.tones`. `MeshCache.key(id, size, color, opts)` + `MeshCache.fetch(key, make) -> Mesh`: the same inputs, the
      same `Mesh` (the key holds `RenderConfig.unit` and the kit's tunables; bounded by `MeshKitConfig.cache_limit`). `MeshNodes.instance(mesh, tint, casts_shadow) -> MeshInstance3D` (the shared toon material, `ToonMaterial.shared()`), `place(node, at_px, yaw)`,
      `surface_frame(at, normal, spin) -> Transform3D` and `decal(size, frame, texture, tint) -> MeshInstance3D` (a flat quad on a surface, `decal.gdshader`, the texture's alpha cuts it), `batch(mesh, count)` / `batch_place` / `batch_show` (many small parts in one draw), `fade(node, amount)`, `glow(node, color, strength)`, `figure(node, on)` (a character's part: the outline draws its silhouette only).
      The mirror's hook that takes the meshes is interface 27. Reached by the domains that own a mesh (Objects, Vehicles, Character and Items' held mesh now; Projectile and Physics for their effects), through the builders they register; Art imports nothing from them.
    - Tuning: `ArtCanvasConfig` (static holder: the art pixel's size, where the light falls from, the turn steps, the drop and cast
	  shadows), `ArtSurfaceConfig` (tone ramp, tone jitter, surface finishes).

    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters (`items/art/`:
    a gun and a grenade painter per weapon style, police, scrap and pipe, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car,
    van, door, wheel, lamp) all render through these; Art imports nothing from other domains.
