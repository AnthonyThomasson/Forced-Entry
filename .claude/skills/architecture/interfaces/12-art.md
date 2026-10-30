12. **Objects / Character / Items / Vehicles → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.render(painter, size, color, facing := Vector2.DOWN, opts := {}) -> Texture2D` — a painter's art
	  at a cardinal facing (the image is turned); furniture, walls, floors. The surface finish rides in the options:
	  `opts.material` (`ArtSurfaceConfig`'s finish, `""` none), handed to the painter as its `material`, the rest as its `opts`.
    - `PixelArt.render_turned(painter, size, color, angle, opts := {}) -> Texture2D` + `PixelArt.snap_angle(angle)`
	  — canonical art lit for a snapped angle, drawn rotated by the caller to the exact one;
	  characters, hands, the guns, a vehicle's body, doors, wheels and lamps.
    - `PixelArt.away_from_light(node) -> Vector2` — which way a cast shadow falls in `node`'s frame (away from
	  `ArtCanvasConfig.light_from`), for every caller that drops a shadow of its own.
    - `PixelCanvas` — the surface a painter draws on (`static paint(canvas, base, material, opts)`): `fill`, `bevel`,
	  `outline`, `surface`, `grain`, `speckle`, `glare`, `cast_shadows` … over the shapes it is handed (a cleared shape is
	  `fill(shape, PixelCanvas.CLEAR, 0)`). `PixelShape` (`art/pixel_shape.gd`) — the shapes: the static factories
	  `PixelShape.rounded` / `ellipse` / `disc` / `bowed` (`bowed` a mask `PixelShape`, the other three `PixelConvexShape`s,
	  `art/pixel_convex_shape.gd`, `extends PixelShape`); `PixelConvexShape.new(rect, x0, x1, y0, y1)` (a shape from its per-row
	  and per-column spans) is built from outside by the Vehicles domain's `art/vehicle_art.gd`; `PixelShape.line_points(a, b) -> Array[Vector2i]` (the
	  points of a 1 px line, the one Bresenham `PixelCanvas.line` draws along) is walked by Objects' `art/decay.gd` for its lines and scratches.
	  The tone ramp is `ArtSurfaceConfig.tones(base)`, and `ArtSurfaceConfig.jitter(rng, col, k)` a colour's signed tone jitter (one
	  `rng` draw within `k`, lightened or darkened by it), which the floor, table and wall painters shift a tone by. **What gives light** (a screen's
	  face, a tube, a bulb, an LED) a painter draws inside `canvas.glowing(draw: Callable, area := Rect2i())`, which marks every pixel
	  the drawing changes as emissive; `PixelArt.emissive(painter, size, color, facing := Vector2.DOWN, opts := {}) -> Texture2D` returns those
	  pixels of `render`'s texture for the same inputs (same paint, cached beside it; transparent elsewhere, null when nothing in it
	  glows), for a caller that draws light sources unshaded. A painter's options carry a big look (a character style's resolved look,
	  a weapon style's colours) as an int handle, never the look itself: `PixelArt.handle(look) -> int` registers it (the look's hash) and
	  `PixelArt.look_of(opts) -> Dictionary` reads `opts.look` back ({} for none); the Character's and Items' painters and their callers use them.
    - `ArtCanvasConfig` (`class_name` static holder) — the art pixel's size, where the light falls from, the turn steps and
	  the drop and cast shadows; `ArtSurfaceConfig` (static holder) — the tone ramp (`tones(base)`), the tone jitter (`jitter(rng, col, k)`) and the surface finishes.
    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters
    (`items/art/`: one gun and one grenade painter per weapon style, police, scrap and pipe, drawing the guns held and dropped and the frag and stun grenades, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car, van, door, wheel, lamp) all render through
    these; Art imports nothing from other domains.
