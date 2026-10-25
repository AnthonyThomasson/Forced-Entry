class_name PhysicsExplosionConfig
## The look of a grenade's burst (scenes/physics/explosion_fx.gd, scorch_decals.gd): the switch,
## its pixel size, the looks per kind and the scorch colour. A `class_name` holder of `static
## var`s, read as `PhysicsExplosionConfig.<name>`; there is no instance and no autoload.

## Master switch: off = `Physics.spawn_explosion` spawns no flash, fireball, smoke or scorch.
static var fx_enabled: bool = true
## Side (px) of one "pixel" of an explosion's look: its discs are stepped rows of this height, like
## the rest of the art.
static var pixel: float = 4.0
## The look of each kind of burst, by kind id (`&"frag"`, `&"stun"`):
##   flash_radius, flash_time, flash_color   the bright disc that fades in `flash_time` s (0 radius
##                                           = none: a stun's flash is the Lighting domain's flash
##                                           light, `docs/lighting.md` L9, not a drawn disc).
##   fireball_radius, fireball_time          the hot puff that swells to `fireball_radius` and fades
##   in `fireball_time` s (0 = none). smoke_puffs, smoke_radius, smoke_time, smoke_alpha,
##   smoke_color   puffs that drift out and swell to `smoke_radius`, fading over `smoke_time` s.
##   scorch_radius                           the black mark left on the floor for good (0 = none).
static var looks: Dictionary = {
	&"frag": {
		"flash_radius": 140.0, "flash_time": 0.12, "flash_color": Color(1.0, 0.96, 0.72),
		"fireball_radius": 100.0, "fireball_time": 0.5, "smoke_puffs": 9, "smoke_radius": 38.0,
		"smoke_time": 4.2, "smoke_alpha": 0.55, "smoke_color": Color(0.27, 0.26, 0.25),
		"scorch_radius": 64.0,
	},
	&"stun": {
		"flash_radius": 0.0, "flash_time": 0.0, "flash_color": Color(1.0, 1.0, 1.0),
		"fireball_radius": 0.0, "fireball_time": 0.0, "smoke_puffs": 3, "smoke_radius": 26.0,
		"smoke_time": 2.6, "smoke_alpha": 0.28, "smoke_color": Color(0.7, 0.7, 0.72),
		"scorch_radius": 0.0,
	},
}
## The scorch mark's colour (its alpha is the mark's darkest, at its core).
static var scorch_color: Color = Color(0.04, 0.035, 0.03, 0.62)
