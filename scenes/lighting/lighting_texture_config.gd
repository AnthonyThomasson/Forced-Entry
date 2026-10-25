class_name LightingTextureConfig
## The Lighting domain's light textures (`docs/lighting.md`): the pool textures per shape and the
## glow and pool profiles they fade along.
##
## A `class_name` holder of `static var`s, read as `LightingTextureConfig.<name>`; there is no
## instance and no autoload.

## The pool textures, by a light's `shape`: a round pool, a wide one (2:1, a screen's spill) and a
## tube's (3:1). Each fades smoothly (no rings) along one of two profiles, given as points (offsets
## out to the rim, 0..1, and the level there, joined linearly):
static var textures: Dictionary = {
	&"round": Vector2i(128, 128),
	&"wide": Vector2i(256, 128),
	&"tube": Vector2i(240, 80),
}
## A low light's glow (a screen, a tube, the flashes): brightest in the middle, fading out to
## nothing at the rim.
static var glow_offsets := PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
static var glow_levels := PackedFloat32Array([1.0, 0.82, 0.58, 0.34, 0.12, 0.0])
## An overhead light's pool (a fixture, a lamp, a street lamp): its cone meets the floor, so it is
## nearly flat out to half its radius, then fades quickly to the rim.
static var pool_offsets := PackedFloat32Array([0.0, 0.5, 0.65, 0.8, 0.92, 1.0])
static var pool_levels := PackedFloat32Array([1.0, 0.96, 0.75, 0.4, 0.12, 0.0])
