class_name LightingConfig
## The Lighting domain's master switch and what its lights share (a `class_name` static holder,
## like the other domains' configs): the dusk and the flashes (`docs/lighting.md`). The room
## fixtures are `LightingFixtureConfig`, the 3D look `Lighting3DConfig`. What each piece's light is
## (where, what colour, how bright, which rhythms) is the piece's own declaration (Objects'
## `get_lights()`), not tuned here.

## Master switch (the Testing domain's `lighting.enabled`): off, `WorldLighting3D.light` builds no
## light, and the world is shown as its art alone.
static var enabled := true
## The ambient: a cool blue-violet, bright enough to read a room and the characters.
static var ambient_color := Color(0.40, 0.37, 0.55)
## The sky light on the street (none in the house: it has a roof): a dim orange-magenta, low in the
## south-west (the front of a house is south), from `sky_from`.
static var sky_color := Color(1.0, 0.5, 0.42)
static var sky_from := Vector2(-0.38, 1.0)
static var sky_energy := 0.42
## The flashes lit by the `shot` and `explosion` events (the pool of them is
## `Lighting3DConfig.flash_lights`). Each kind: colour, energy, pool diameter (px; an
## explosion's at least `radius × reach_per_radius`), how long (s) it holds its full energy (`hold`,
## none when absent) and how long (s) it then falls off to dark (`life`). The stun's is its burst's
## whole look (no drawn disc, `PhysicsExplosionConfig.looks`): a far brighter white held an
## instant, then faded. A row with `wash` is a white-out: the toon light adds its colour to the
## surface (not times it) in two flat bands, so what it reaches is flat white and fades; a row
## without is the surface lit by the flash's colour, past the dusk's cap.
static var flashes: Dictionary = {
	&"shot": {
		"color": Color(1.0, 0.82, 0.55),
		"energy": 1.6,
		"reach": 340.0,
		"life": 0.07,
	},
	&"frag": {
		"color": Color(1.0, 0.62, 0.3),
		"energy": 2.6,
		"reach": 600.0,
		"reach_per_radius": 4.0,
		"life": 0.5,
	},
	&"stun": {
		"color": Color(0.92, 0.95, 1.0),
		"energy": 8.0,
		"reach": 700.0,
		"reach_per_radius": 3.5,
		"hold": 0.08,
		"life": 0.7,
		"wash": true,
	},
}
## A floor's walls and wear reach this far (px) past its rect: a house's cover is its rooms grown
## by it.
static var floor_reach := 8.0
