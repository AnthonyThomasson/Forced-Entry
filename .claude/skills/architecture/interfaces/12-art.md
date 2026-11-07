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
    - Tuning: `ArtCanvasConfig` (static holder: the art pixel's size, where the light falls from, the turn steps, the drop and cast
	  shadows), `ArtSurfaceConfig` (tone ramp, tone jitter, surface finishes).

    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters (`items/art/`:
    a gun and a grenade painter per weapon style, police, scrap and pipe, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car,
    van, door, wheel, lamp) all render through these; Art imports nothing from other domains.
