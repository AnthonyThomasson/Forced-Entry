extends RefCounted
## The shared reads of the 3D lighting tests (`tests/lighting/light_3d_*_test.gd`; #193 phase 3).
## Not a test.
## What the tests read: `WorldLighting3D` (class_name, `scenes/lighting/`), built for a 2D test
## world
## into a 3D viewport of its own (`light`):
##   - `lights() -> Array`: the `OmniLight3D`s it gave a piece or a room fixture;
##   - `fixtures() -> Array`: `{ room, light }` per room fixture;
##   - `sun() -> DirectionalLight3D`: the sky;
## - `budget() -> Dictionary`: `{ per_floor, dropped }`, `dropped` `{ piece, index }` per declared
## light
##     left without a light;
##   - `shadowed_count()`, `on_count()`: what the cost cap chose;
##   - `choose()`: choose again now (the view's focus is the `focus` Callable the test gave).
## A light's 3D place is its 2D `(x, y)` times `RenderConfig.unit`, `x` and `z`, at its height `y`.


## Light the 2D test world `t.world` into a 3D viewport of its own: `rooms` the fixtures' rooms,
## `focus` a `Callable() -> Vector2` (none: every light on) with a camera `view_px` tall to say how
## far it sees (none: it sees everything). The lighting, or null (the test failed).
static func light(
	t: TestContext, rooms: Array = [], focus := Callable(), view_px := 0.0
) -> WorldLighting3D:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	if view_px > 0.0:
		# A camera `view_px` units tall: the lights beyond its reach of the focus are off.
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = view_px
		view.add_child(camera)
	var lighting := WorldLighting3D.light(view, t.world, 1, rooms, focus)
	t.require(lighting != null, "the 3D lighting is built under the viewport")
	return lighting


## The 2D point a 3D light stands over (px).
static func ground_of(l: Node3D) -> Vector2:
	return Vector2(l.position.x, l.position.z) / RenderConfig.unit


## The lights of `lighting` whose 2D place is within `slack` px of `at`.
static func near(lighting: WorldLighting3D, at: Vector2, slack := 1.0) -> Array:
	return lighting.lights().filter(
		func(l: Node3D) -> bool: return ground_of(l).distance_to(at) <= slack
	)


## The lights of `lighting` given to `piece` (each says its piece and the index of the declared
## light in its `get_lights()`: the metas `piece` and `index`).
static func lights_of(lighting: WorldLighting3D, piece: Node) -> Array:
	return lighting.lights().filter(
		func(l: Node3D) -> bool: return l.has_meta(&"piece") and l.get_meta(&"piece") == piece
	)


## How far (px) from a light on the floor its pool reaches: its range, less the height it hangs at.
static func floor_reach(l: OmniLight3D) -> float:
	var along := l.omni_range * l.omni_range - l.position.y * l.position.y
	return sqrt(maxf(along, 0.0)) / RenderConfig.unit
