class_name Lighting3DConfig
## The Lighting domain's 3D dusk (#193 phase 3, `docs/lighting.md` "The 3D lighting"): the sun's
## angle and shadow, how high each kind of light hangs, how a pool falls off, and what the lights
## cost. The dusk's colours and energies are `LightingConfig`'s (`ambient_color`, `sky_color`,
## `sky_from`, `sky_energy`); what each piece gives is its own `get_lights()`. A `class_name`
## holder of `static var`s, read as `Lighting3DConfig.<name>` (ADR 0003).

## The sun's elevation above the horizon, degrees: high, so the shadow a wall or a person throws is
## short (a wall of 96 throws one `96 / tan(elevation)` long) like the 2D drop shadow, not the
## streak of a low sun.
static var sun_elevation: float = 76.0
## The sun's shadow: how far from the camera it reaches and its biases (3D units).
static var shadow_max_distance: float = 1600.0
static var shadow_bias: float = 0.6
static var shadow_normal_bias: float = 1.5
## How high (px) a light hangs above the floor when its declaration gives no `lift` (a piece's
## `get_lights()` says where its glowing part is, in px above the floor: a lamp's bulb at its
## shade, a screen's face, a street lamp's head at the top of its pole): by its `height` kind
## (`overhead`: above the heads, `low`: a screen, a tube, a strip) and a street lamp's head (its
## `street` flag).
static var overhead_height: float = 60.0
static var low_height: float = 22.0
static var street_height: float = 70.0
## A room's ceiling fixture: the bulb hangs at the ceiling (`LightingFixtureConfig.bulb_height`),
## but its LIGHT, the one that casts a shadow, stands `fixture_height` px up: a light at the ceiling
## throws the long, hard shadow of a lamp in a small room over every table, a wardrobe's across the
## floor (a 70 tall wardrobe 100 px from a light at 104 throws 300), where 2D's drop shadows are a
## few px under the piece. Raised, the shadow is as short as 2D's (the same wardrobe's is 21 at 400)
## and the pool on the floor is the same (the toon light takes its shape from the light's ground
## distance, `ToonLight.specular`).
static var fixture_height: float = 400.0
## A pool reaches `radius * range_scale` px along the floor (the 2D pool's radius is where it fades
## out). Its fall-off is linear from the light to the rim, scaled by a slope and cut at 1: an
## `overhead` pool (slope 2) is flat to half its radius, a low glow (slope 1) fades from its middle.
static var range_scale: float = 1.3
static var overhead_slope: float = 2.0
static var low_slope: float = 1.0
## The flashes of a shot and a burst (`LightingConfig.flashes`): the pool is this many
## `OmniLight3D`s (the oldest is dropped for a new flash, so a firefight never passes it), each hung
## `flash_height` px up (a hand's, a blast's) and not cast: unshadowed, outside the shadow cap, kept
## to its room by the room map. A flash whose position is within `flash_room_slack` px outside a
## room's rect (a muzzle in a doorway or at a wall) lights that room, else it is a street flash.
static var flash_lights: int = 4
static var flash_height: float = 30.0
static var flash_room_slack: float = 8.0
## How dark a ceiling fixture's shadow is (`OmniLight3D.shadow_opacity`, 1 fully dark): below 1 the
## floor under a table or a chair keeps part of the pool's light, its colour a step down, and not
## the cold ambient alone (the 2D render has no such blob).
static var fixture_shadow_opacity: float = 0.6


## How high (px) a light of `kind` (`overhead`, `low` or `street`) hangs.
static func height_of(kind: StringName) -> float:
	match kind:
		&"overhead":
			return overhead_height
		&"street":
			return street_height
	return low_height
