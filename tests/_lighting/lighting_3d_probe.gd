extends RefCounted
## The shared reads of the 3D lighting tests (`tests/lighting/light_3d_*_test.gd`; #193 phase 3).
## Not a test.
## What the tests read: `WorldLighting3D` (class_name, `scenes/lighting/`), built for a 2D test
## world
## into a 3D viewport of its own (`light`):
##   - `lights() -> Array`: the `OmniLight3D`s it gave a piece or a room fixture;
##   - `fixtures() -> Array`: `{ room, light }` per room fixture;
##   - `sun() -> DirectionalLight3D`: the sky;
##   - `shadowed_count()`, `on_count()`, `in_view_count()`: what the cost cap chose;
##   - `flashes() -> Array`, `flash_count()`: the pooled flash lights and how many are lit;
##   - `choose(snap)`: choose again now (the view's focus is the `focus` Callable the test gave;
##     `snap` puts every light at its fade's end).
## A flash is lit now when it is shown with energy (`lit`).
## A light's 3D place is its 2D `(x, y)` times `RenderConfig.unit`, `x` and `z`, at its height `y`.

## How far (px) from the event a flash's light may stand.
const FLASH_NEAR := 24.0


## Light the 2D test world `t.world` into a 3D viewport of its own: `rooms` the fixtures' rooms,
## `focus` a `Callable() -> Vector2` (none: every light on) with a camera `view_px` tall to say how
## far it sees (none: it sees everything), of `world` (default the test's). The lighting, or null
## (the test failed).
static func light(
	t: TestContext, rooms: Array = [], focus := Callable(), view_px := 0.0, world: Node2D = null
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
	var lighting := WorldLighting3D.light(
		view,
		world if world != null else t.world,
		1,
		rooms,
		focus,
	)
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


## The id of the room (its index in `rooms` plus one, 0 for none) a light stands in: its meta
## `room`.
static func room_of(l: OmniLight3D) -> int:
	return int(l.get_meta(&"room"))


## The id the room map gives world point `at` in `rooms` (`{ key, rect }`): index plus one, 0 none.
static func room_at(rooms: Array, at: Vector2) -> int:
	for k in rooms.size():
		if (rooms[k]["rect"] as Rect2).has_point(at):
			return k + 1
	return 0


## Whether a light is a street light, as the toon light reads it: the low bit of the code packed in
## its specular (`ToonLight.specular`: the code is room * 2 + street).
static func street_of(l: OmniLight3D) -> bool:
	return int(decode(l)["code"]) % 2 == 1


## Whether flash light `l` is lit now.
static func lit(l: Light3D) -> bool:
	return l.visible and l.light_energy > 0.01


## The lit flash of `lighting` within `FLASH_NEAR` of `at` (null for none).
static func flash_at(lighting: WorldLighting3D, at: Vector2) -> OmniLight3D:
	for l: OmniLight3D in lighting.flashes():
		if lit(l) and ground_of(l).distance_to(at) <= FLASH_NEAR:
			return l
	return null


## Whether any flash of `lighting` is lit.
static func any_lit(lighting: WorldLighting3D) -> bool:
	return lighting.flashes().any(func(l: OmniLight3D) -> bool: return lit(l))


## What a flash light is to the toon light: 1 a tinted flash, 2 a white-out (`light_specular` is
## `(slope + kind / 4 + 4 * code) / 2`); 0 for a lamp's light.
static func flash_kind(l: OmniLight3D) -> int:
	var amount := l.light_specular * 2.0
	var packed := amount - 4.0 * floorf(amount / 4.0 + 0.001)
	return int(floorf(fposmod(packed + 0.01, 1.0) * 4.0 + 0.5))


## What the toon light reads of a positional light's `light_specular` (`ToonLight.specular`, decoded
## as `toon_common.gdshaderinc` does): `{ slope, kind, code, ratio, height }`: the pool's flatness,
## 0 a lamp, 1 a tinted flash, 2 a white-out, the room id times two plus one for a street light, the
## light's height over its pool's rim and its height (3D units).
static func decode(l: OmniLight3D) -> Dictionary:
	var amount := l.light_specular * 2.0
	var whole := floorf(amount / 4.0 + 0.001)
	var high := floorf(whole / 65_536.0 + 0.0001)
	var rest := whole - high * 65_536.0
	var steps := floorf(rest / 1024.0 + 0.0001)
	var packed := amount - 4.0 * whole
	return {
		"slope": floorf(packed + 0.01),
		"kind": floorf(fposmod(packed + 0.01, 1.0) * 4.0 + 0.5),
		"code": int(rest - steps * 1024.0),
		"ratio": steps / 16.0,
		"height": 4.0 * pow(1.4, high),
	}
