class_name LightingFixtureConfig
## The Lighting domain's room fixtures (`docs/lighting.md`): a ceiling fixture's colour, energy,
## reach and rhythms.
##
## A `class_name` holder of `static var`s, read as `LightingFixtureConfig.<name>`; there is no
## instance and no autoload.

## A room no piece lights (none of its lights is a kept `room_light`) gets a ceiling fixture at its
## centre: a bare bulb on its flex (glowing) and its light, overhead: shadowed by the walls
## only and pooling downward. Its pool spans the room and barely past its walls: the room's longer
## side × `reach_scale` + `reach_pad`, clamped.
static var color := Color(1.0, 0.62, 0.22)
static var energy := 0.8
static var reach_scale := 1.1
static var reach_pad := 60.0
static var reach_range := Vector2(300.0, 900.0)
## The rhythms a fixture's light is drawn from, by weight (the modes in light_rhythm.gd's header).
static var rhythms: Array = [[&"steady", 12.0], [&"failing", 1.0]]
## The bulb the 3D render hangs at a fixture: `bulb_radius` px across its middle,
## `bulb_height` px up (over the walls' tops), glowing the
## light's colour lightened by `bulb_lighten` and brightened `bulb_glow`.
static var bulb_radius := 3.0
static var bulb_height := 104.0
static var bulb_lighten := 0.55
static var bulb_glow := 1.6
## A fixture's LIGHT, the one that casts a shadow, is not at its bulb: a light at the ceiling
## (`bulb_height`) throws the long, hard shadow of a lamp in a small room (a 70 tall wardrobe 100 px
## away: 230 px), where a drop shadow is a few px under the piece. So it stands
## `shadow_height` px up, higher in a bigger room: far enough that a wall (96) at the room's
## half-length throws only `shadow_far` px, up to `shadow_height_max` (a 96 wall 250 px away then
## throws 48). The pool on the floor is the same whatever the height (`ToonLight.specular`).
static var shadow_height := 400.0
static var shadow_height_max := 600.0
static var shadow_far := 30.0
## How dark a fixture's shadow is (`OmniLight3D.shadow_opacity`, 1 fully dark): below 1 the floor
## under a table or a chair keeps part of the pool's light, its colour a step down, and not the cold
## ambient alone.
static var shadow_opacity := 0.6


## The height (px) of the shadow light of a fixture in a room `longer` px on its longer side.
static func shadow_height_for(longer: float, wall := 96.0) -> float:
	return clampf(wall * (1.0 + longer * 0.5 / shadow_far), shadow_height, shadow_height_max)
