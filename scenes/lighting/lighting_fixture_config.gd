class_name LightingFixtureConfig
## The Lighting domain's room fixtures (`docs/lighting.md`): a ceiling fixture's colour, energy,
## reach and rhythms.
##
## A `class_name` holder of `static var`s, read as `LightingFixtureConfig.<name>`; there is no
## instance and no autoload.

## A room no piece lights (none of its lights is a kept `room_light`) gets a ceiling fixture at its
## centre: a bare bulb on its flex (drawn unshaded) and its light, overhead: shadowed by the walls
## only and pooling downward. Its pool spans the room and barely past its walls: the room's longer
## side × `reach_scale` + `reach_pad`, clamped.
static var color := Color(1.0, 0.62, 0.22)
static var energy := 0.8
static var reach_scale := 1.1
static var reach_pad := 60.0
static var reach_range := Vector2(300.0, 900.0)
## The rhythms a fixture's light is drawn from, by weight (the modes in light_rhythm.gd's header).
static var rhythms: Array = [[&"steady", 12.0], [&"failing", 1.0]]
## The bulb the 3D render hangs at a fixture (the 2D glyph's): `bulb_radius` px across its middle,
## `bulb_height` px up (over the walls' tops, as the glyph is drawn over everything), glowing the
## light's colour lightened by `bulb_lighten` and brightened `bulb_glow`.
static var bulb_radius := 3.0
static var bulb_height := 104.0
static var bulb_lighten := 0.55
static var bulb_glow := 1.6
